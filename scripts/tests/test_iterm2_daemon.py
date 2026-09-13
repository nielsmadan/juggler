import asyncio
import concurrent.futures
import importlib.util
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import AsyncMock, patch


SCRIPT = Path(__file__).resolve().parents[2] / "juggler/Resources/iterm2_daemon.py"
SPEC = importlib.util.spec_from_file_location("juggler_iterm2_daemon", SCRIPT)
DAEMON = importlib.util.module_from_spec(SPEC)
with patch.dict(sys.modules, {"iterm2": types.ModuleType("iterm2")}):
    SPEC.loader.exec_module(DAEMON)


class DaemonSocketTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="iterm2-", dir="/tmp")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "daemon.sock"

    def daemon(self):
        daemon = DAEMON.iTerm2Daemon(str(self.path), None)
        self.addCleanup(daemon.stop)
        return daemon

    def assert_connects_to(self, daemon):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(2)
            client.connect(str(self.path))
            client.sendall(b"ping")
            connection, _ = daemon.server.accept()
            with connection:
                connection.settimeout(2)
                self.assertEqual(connection.recv(4), b"ping")

    def test_published_socket_accepts_connections_and_records_owner(self):
        daemon = self.daemon()
        daemon._bind_socket()
        self.assert_connects_to(daemon)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(Path(str(self.path) + ".pid").read_text(), str(os.getpid()))

    def test_retiring_daemon_preserves_replacement_socket_and_pid(self):
        old = self.daemon()
        old._bind_socket()
        replacement = self.daemon()
        replacement._bind_socket()
        old.stop()
        self.assert_connects_to(replacement)
        self.assertEqual(Path(str(self.path) + ".pid").read_text(), str(os.getpid()))

    def test_owner_stop_removes_its_socket_and_pid(self):
        daemon = self.daemon()
        daemon._bind_socket()
        daemon.stop()
        self.assertFalse(self.path.exists())
        self.assertFalse(Path(str(self.path) + ".pid").exists())

    def test_stop_closes_server_after_socket_directory_is_removed(self):
        daemon = self.daemon()
        daemon._bind_socket()
        self.directory.cleanup()
        daemon.stop()
        self.assertEqual(daemon.server.fileno(), -1)

    def test_daemon_whose_parent_died_before_readiness_exits(self):
        daemon = self.daemon()
        daemon._bind_socket()
        with patch.object(DAEMON.os, "getppid", return_value=1), \
                patch.object(DAEMON.asyncio, "sleep", new=AsyncMock()), \
                patch.object(DAEMON.os, "_exit", side_effect=SystemExit(0)):
            with self.assertRaises(SystemExit) as exited:
                asyncio.run(daemon._monitor_parent())
        self.assertEqual(exited.exception.code, 0)
        self.assertFalse(self.path.exists())

    def test_termination_signals_exit_cleanly_and_remove_owned_files(self):
        runner = """
import asyncio, importlib.util, sys, types
async def get_app(connection):
    return None
sys.modules["iterm2"] = types.SimpleNamespace(async_get_app=get_app)
spec = importlib.util.spec_from_file_location("daemon", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
sys.argv = [sys.argv[1], sys.argv[2]]
asyncio.run(module.main(None))
"""
        for sig in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=sig):
                child = subprocess.Popen(
                    [sys.executable, "-u", "-c", runner, str(SCRIPT), str(self.path)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                )
                try:
                    with selectors.DefaultSelector() as selector:
                        selector.register(child.stderr, selectors.EVENT_READ)
                        self.assertTrue(selector.select(timeout=5), "daemon did not become ready")
                    self.assertEqual(child.stderr.readline().decode().strip(), f"Daemon listening on {self.path}")
                    child.send_signal(sig)
                    self.assertEqual(child.wait(timeout=5), 0)
                    self.assertFalse(self.path.exists())
                    self.assertFalse(Path(str(self.path) + ".pid").exists())
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.wait(timeout=5)
                    child.stderr.close()

    def test_simultaneous_binds_all_succeed_and_retire_without_removing_the_winner(self):
        count = 8
        barrier = threading.Barrier(count, timeout=5)
        daemons = [self.daemon() for _ in range(count)]
        real_socket = socket.socket

        class SynchronizedSocket(real_socket):
            def bind(self, address):
                super().bind(address)
                barrier.wait()

        with patch.object(DAEMON.socket, "socket", SynchronizedSocket):
            with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool:
                list(pool.map(lambda daemon: daemon._bind_socket(), daemons))
        inode = self.path.stat().st_ino
        winner = next(daemon for daemon in daemons if daemon.socket_inode == inode)
        for daemon in daemons:
            if daemon is not winner:
                daemon.stop()
        self.assert_connects_to(winner)

    def test_failed_publication_preserves_the_existing_daemon(self):
        current = self.daemon()
        current._bind_socket()
        replacement = self.daemon()
        with patch.object(DAEMON.os, "replace", side_effect=OSError("publication failed")):
            with self.assertRaisesRegex(OSError, "publication failed"):
                replacement._bind_socket()
        replacement.stop()
        self.assert_connects_to(current)


if __name__ == "__main__":
    unittest.main()
