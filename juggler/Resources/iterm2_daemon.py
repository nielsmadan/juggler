#!/usr/bin/env python3
"""
Persistent iTerm2 daemon for Juggler.
Maintains connection to iTerm2 and handles commands via Unix socket.
Event-driven architecture: pushes focus and terminal_info events.
"""

from __future__ import annotations

import asyncio
import json
import os
import signal
import socket
import sys
from pathlib import Path
from typing import Any, Optional

import iterm2


class iTerm2Daemon:
    def __init__(self, socket_path: str, connection: iterm2.Connection) -> None:
        self.socket_path: Path = Path(socket_path)
        self.connection: iterm2.Connection = connection
        self.app: Optional[iterm2.App] = None
        self.server: Optional[socket.socket] = None
        self.running: bool = True
        # Track active highlight reset tasks to cancel on new highlights
        self.active_tab_reset_tasks: dict[str, asyncio.Task] = {}
        self.active_pane_reset_tasks: dict[str, asyncio.Task] = {}
        # Track event subscribers (persistent connections)
        self.event_subscribers: list[tuple[socket.socket, asyncio.Lock]] = []

    async def start(self) -> None:
        self.app = await iterm2.async_get_app(self.connection)

        self.socket_path.unlink(missing_ok=True)

        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(self.socket_path))
        os.chmod(str(self.socket_path), 0o600)
        self.server.listen(5)
        self.server.setblocking(False)

        print(f"Daemon listening on {self.socket_path}", file=sys.stderr)

        asyncio.create_task(self.run_focus_monitor())
        asyncio.create_task(self.run_session_monitor())
        asyncio.create_task(self.run_layout_monitor())
        asyncio.create_task(self._monitor_parent())

        loop = asyncio.get_running_loop()
        while self.running:
            try:
                client, _ = await loop.sock_accept(self.server)
                asyncio.create_task(self.handle_client(client))
            except Exception as e:
                if self.running:
                    print(f"Accept error: {e}", file=sys.stderr)

    async def handle_client(self, client: socket.socket) -> None:
        loop = asyncio.get_running_loop()
        try:
            data = await loop.sock_recv(client, 65536)
            if not data:
                return

            request = json.loads(data.decode("utf-8").strip())

            # Handle subscribe specially - keep connection open
            if request.get("command") == "subscribe":
                await self.handle_subscription(client)
                return  # Don't close connection

            response = await self.process_command(request)

            # Add newline for consistent protocol
            await loop.sock_sendall(client, json.dumps(response).encode("utf-8") + b"\n")
        except Exception as e:
            error_response = {"status": "error", "message": str(e)}
            try:
                await loop.sock_sendall(client, json.dumps(error_response).encode("utf-8") + b"\n")
            except Exception:
                pass
        finally:
            client.close()

    async def handle_subscription(self, client: socket.socket) -> None:
        """Handle an event subscription - keep connection open for push events."""
        loop = asyncio.get_running_loop()
        write_lock = asyncio.Lock()

        try:
            await loop.sock_sendall(client, json.dumps({"status": "ok"}).encode("utf-8") + b"\n")
        except Exception as e:
            print(f"Failed to send subscription ack: {e}", file=sys.stderr)
            client.close()
            return

        subscriber = (client, write_lock)
        self.event_subscribers.append(subscriber)

        # Keep connection alive by waiting for it to close
        try:
            while self.running:
                client.setblocking(False)
                try:
                    data = await loop.sock_recv(client, 1)
                    if not data:
                        break
                except BlockingIOError:
                    pass
                await asyncio.sleep(1)
        except Exception:
            pass
        finally:
            if subscriber in self.event_subscribers:
                self.event_subscribers.remove(subscriber)
            try:
                client.close()
            except Exception:
                pass

    async def process_command(self, request: dict[str, Any]) -> dict[str, Any]:
        command = request.get("command")

        if command == "ping":
            return {"status": "ok"}

        elif command == "get_session_info":
            session_id = request.get("session_id")
            return await self.get_session_info(session_id)

        elif command == "activate":
            session_id = request.get("session_id")
            return await self.activate_session(session_id)

        elif command == "highlight":
            session_id = request.get("session_id")
            tab_config = request.get("tab")
            pane_config = request.get("pane")
            return await self.highlight_session(session_id, tab_config, pane_config)

        elif command == "reset":
            session_id = request.get("session_id")
            return await self.reset_highlight(session_id)

        elif command == "subscribe":
            # Handled specially in handle_client
            return None

        else:
            return {"status": "error", "message": f"Unknown command: {command}"}

    async def run_focus_monitor(self) -> None:
        """Monitor iTerm2 focus changes and push events."""
        consecutive_failures: int = 0
        while self.running:
            try:
                async with iterm2.FocusMonitor(self.connection) as monitor:
                    consecutive_failures = 0
                    while self.running:
                        update = await monitor.async_get_next_update()
                        if update.active_session_changed:
                            session_id = update.active_session_changed.session_id
                            await self.push_event({
                                "event": "focus_changed",
                                "session_id": session_id
                            })
            except Exception as e:
                consecutive_failures += 1
                if consecutive_failures >= 3:
                    print(f"Focus monitor failed {consecutive_failures} times, exiting for restart", file=sys.stderr)
                    self.stop()
                    sys.exit(1)
                print(f"Focus monitor error: {e}, restarting in 5s...", file=sys.stderr)
                if self.running:
                    await asyncio.sleep(5)

    async def run_session_monitor(self) -> None:
        """Monitor iTerm2 session terminations and push events."""
        consecutive_failures: int = 0
        while self.running:
            try:
                async with iterm2.SessionTerminationMonitor(self.connection) as monitor:
                    consecutive_failures = 0
                    while self.running:
                        session_id = await monitor.async_get()
                        await self.push_event({
                            "event": "session_terminated",
                            "session_id": session_id
                        })
            except Exception as e:
                consecutive_failures += 1
                if consecutive_failures >= 3:
                    print(f"Session monitor failed {consecutive_failures} times, giving up", file=sys.stderr)
                    break
                print(f"Session monitor error: {e}, restarting in 5s...", file=sys.stderr)
                if self.running:
                    await asyncio.sleep(5)

    async def run_layout_monitor(self) -> None:
        """Monitor layout changes for faster session close detection.

        SessionTerminationMonitor waits for the process to exit (~5s).
        LayoutChangeMonitor fires immediately when a window/tab closes,
        so we can detect gone sessions much faster.
        """
        known_sessions: set[str] = self._get_all_session_ids()
        while self.running:
            try:
                async with iterm2.LayoutChangeMonitor(self.connection) as monitor:
                    while self.running:
                        await monitor.async_get()
                        current_sessions = self._get_all_session_ids()
                        gone = known_sessions - current_sessions
                        for session_id in gone:
                            await self.push_event({
                                "event": "session_terminated",
                                "session_id": session_id
                            })
                        known_sessions = current_sessions
            except Exception as e:
                print(f"Layout monitor error: {e}", file=sys.stderr)
                if self.running:
                    await asyncio.sleep(5)

    def _get_all_session_ids(self) -> set[str]:
        """Get all current iTerm2 session IDs."""
        sessions: set[str] = set()
        for window in self.app.terminal_windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    sessions.add(session.session_id)
        return sessions

    async def push_event(self, event: dict[str, Any]) -> None:
        if not self.event_subscribers:
            return

        message = json.dumps(event).encode("utf-8") + b"\n"
        loop = asyncio.get_running_loop()
        dead_subscribers: list[tuple[socket.socket, asyncio.Lock]] = []

        # Iterate over a copy to avoid mutation during await points
        for subscriber in list(self.event_subscribers):
            client, write_lock = subscriber
            try:
                async with write_lock:
                    await loop.sock_sendall(client, message)
            except Exception:
                dead_subscribers.append(subscriber)

        for sub in dead_subscribers:
            if sub in self.event_subscribers:
                self.event_subscribers.remove(sub)

    async def get_session_info(self, session_id: str) -> dict[str, Any]:
        """Get info for ONE session - direct API call."""
        uuid = self._extract_uuid(session_id)
        session = self.app.get_session_by_id(uuid)

        if not session:
            return {"status": "error", "message": "Session not found"}

        tab = session.tab
        window = tab.window if tab else None

        tab_name = await tab.async_get_variable("title") if tab else "Unknown"
        window_name = await self._get_window_name(window) if window else "Unknown"

        pane_index = tab.sessions.index(session) if tab else 0
        pane_count = len(tab.sessions) if tab else 1

        return {
            "status": "ok",
            "session_id": session_id,
            "tab_name": tab_name or "Tab",
            "window_name": window_name,
            "pane_index": pane_index,
            "pane_count": pane_count
        }

    async def _get_window_name(self, window) -> str:
        if not window:
            return "Unknown"
        window_title = await window.async_get_variable("titleOverrideFormat")
        if window_title:
            return window_title
        window_number = await window.async_get_variable("number")
        if window_number is not None:
            return f"Window {window_number}"
        return "Window"

    async def activate_session(self, session_id: str) -> dict[str, Any]:
        uuid = self._extract_uuid(session_id)
        session = self.app.get_session_by_id(uuid)

        if not session:
            return {"status": "error", "message": "Session not found"}

        tab = session.tab
        window = tab.window if tab else None

        await self.app.async_activate()

        if window:
            await window.async_activate()

        # Activate the session (selects tab and pane)
        await session.async_activate(select_tab=True, order_window_front=True)

        return {"status": "ok"}

    async def highlight_session(
        self, session_id: str, tab_config: Optional[dict[str, Any]], pane_config: Optional[dict[str, Any]]
    ) -> dict[str, Any]:
        uuid = self._extract_uuid(session_id)
        session = self.app.get_session_by_id(uuid)

        if not session:
            return {"status": "error", "message": "Session not found"}

        tab = session.tab
        tab_id = tab.tab_id if tab else None

        if tab_id and tab_id in self.active_tab_reset_tasks:
            self.active_tab_reset_tasks[tab_id].cancel()
            del self.active_tab_reset_tasks[tab_id]

        if uuid in self.active_pane_reset_tasks:
            self.active_pane_reset_tasks[uuid].cancel()
            del self.active_pane_reset_tasks[uuid]

        original_bg = None
        if pane_config and pane_config.get("enabled"):
            try:
                profile = await session.async_get_profile()
                original_bg = await profile.async_get_background_color()
            except Exception:
                original_bg = iterm2.Color(0, 0, 0)

        change = iterm2.LocalWriteOnlyProfile()

        if tab_config and tab_config.get("enabled"):
            color = tab_config.get("color", [255, 165, 0])
            change.set_tab_color(iterm2.Color(color[0], color[1], color[2]))
            change.set_use_tab_color(True)
            duration = tab_config.get("duration", 2.0)
            if tab_id:
                task = asyncio.create_task(self._reset_tab_after_delay(session, tab_id, duration))
                self.active_tab_reset_tasks[tab_id] = task

        if pane_config and pane_config.get("enabled"):
            color = pane_config.get("color", [255, 165, 0])
            change.set_background_color(iterm2.Color(color[0], color[1], color[2]))
            duration = pane_config.get("duration", 2.0)
            task = asyncio.create_task(self._reset_pane_after_delay(session, uuid, duration, original_bg))
            self.active_pane_reset_tasks[uuid] = task

        await session.async_set_profile_properties(change)

        return {"status": "ok"}

    async def _apply_profile_with_retry(
        self, session: iterm2.Session, profile: iterm2.LocalWriteOnlyProfile,
        label: str, escape_fallback: Optional[bytes] = None
    ) -> None:
        """Apply profile properties with one retry and optional escape sequence fallback."""
        try:
            await session.async_set_profile_properties(profile)
        except Exception as e:
            print(f"{label} failed, retrying: {e}", file=sys.stderr)
            try:
                await asyncio.sleep(1)
                await session.async_set_profile_properties(profile)
            except Exception as e2:
                if escape_fallback:
                    print(f"{label} retry failed, using escape sequence: {e2}", file=sys.stderr)
                    try:
                        await session.async_inject(escape_fallback)
                    except Exception:
                        print(f"All {label} attempts failed", file=sys.stderr)
                else:
                    print(f"{label} retry also failed: {e2}", file=sys.stderr)

    async def _reset_tab_after_delay(self, session: iterm2.Session, tab_id: str, duration: float) -> None:
        try:
            await asyncio.sleep(duration)
            reset = iterm2.LocalWriteOnlyProfile()
            reset.set_use_tab_color(False)
            await self._apply_profile_with_retry(session, reset, f"Tab reset ({tab_id})")
        except asyncio.CancelledError:
            pass
        finally:
            self.active_tab_reset_tasks.pop(tab_id, None)

    async def _reset_pane_after_delay(
        self, session: iterm2.Session, uuid: str, duration: float, original_color: Optional[iterm2.Color]
    ) -> None:
        try:
            await asyncio.sleep(duration)
            reset = iterm2.LocalWriteOnlyProfile()
            reset.set_background_color(original_color)
            await self._apply_profile_with_retry(
                session, reset, f"Pane reset ({uuid})",
                escape_fallback=b'\033]1337;SetColors=bg=default\a'
            )
        except asyncio.CancelledError:
            pass
        finally:
            self.active_pane_reset_tasks.pop(uuid, None)

    async def reset_highlight(self, session_id: str) -> dict[str, Any]:
        uuid = self._extract_uuid(session_id)
        session = self.app.get_session_by_id(uuid)

        if not session:
            return {"status": "error", "message": "Session not found"}

        await session.async_inject(b'\033]1337;SetColors=bg=default\a')

        return {"status": "ok"}

    async def _monitor_parent(self) -> None:
        """Exit if parent process dies (orphan detection)."""
        parent_pid = os.getppid()
        while self.running:
            await asyncio.sleep(5)
            if os.getppid() != parent_pid:
                print("Parent process gone, exiting", file=sys.stderr)
                self.stop()
                sys.exit(0)

    def _extract_uuid(self, session_id: str) -> str:
        """Extract UUID from 'w0t0p0:UUID' format."""
        if ":" in session_id:
            return session_id.split(":", 1)[1]
        return session_id

    def stop(self) -> None:
        self.running = False
        if self.server:
            self.server.close()
        self.socket_path.unlink(missing_ok=True)


# Hard ceiling for the initial iTerm2 connection. The iterm2 library with
# retry=True will spin forever on connection refused / 401, so we need our
# own timeout. Once the daemon is connected and serving, this alarm is
# cleared — daemon uptime is unbounded after that.
CONNECTION_TIMEOUT_SECONDS = 30


def _emit_structured_error(phase: str, detail: str) -> None:
    """Write a single JSON line to stderr that Swift can parse and surface."""
    print(json.dumps({"phase": phase, "detail": detail}), file=sys.stderr, flush=True)


def _connection_timeout_handler(_sig: int, _frame: Any) -> None:
    _emit_structured_error(
        "connection_timeout",
        f"Could not connect to iTerm2 within {CONNECTION_TIMEOUT_SECONDS}s. "
        "iTerm2 may not be running, the Python API may be disabled, or authorization was denied.",
    )
    sys.exit(1)


async def main(connection: iterm2.Connection) -> None:
    # We made it past the websocket handshake; clear the connection watchdog.
    signal.alarm(0)

    if len(sys.argv) < 2:
        print("Usage: iterm2_daemon.py <socket_path>", file=sys.stderr)
        sys.exit(1)

    socket_path = sys.argv[1]
    daemon = iTerm2Daemon(socket_path, connection)

    def signal_handler(sig: int, frame: Any) -> None:
        daemon.stop()
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    await daemon.start()


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, _connection_timeout_handler)
    signal.alarm(CONNECTION_TIMEOUT_SECONDS)
    try:
        iterm2.run_until_complete(main, retry=True)
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        _emit_structured_error("fatal", f"{type(exc).__name__}: {exc}")
        sys.exit(1)
