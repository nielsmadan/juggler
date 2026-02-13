"""
Juggler watcher for Kitty terminal.

This is a Kitty "watcher" script that runs inside Kitty's process.
It posts focus and close events to Juggler's HTTP server so Juggler
can track which Kitty window is active and detect session termination.

Install by adding to kitty.conf:
    watcher ~/.config/kitty/juggler_watcher.py
"""

import subprocess


JUGGLER_PORT = 7483
JUGGLER_URL = f"http://localhost:{JUGGLER_PORT}/kitty-event"


def _post_event(event: str, window_id: int) -> None:
    """Fire-and-forget POST to Juggler. Never raises."""
    try:
        payload = f'{{"event":"{event}","window_id":"{window_id}"}}'
        subprocess.Popen(
            [
                "curl", "-s", "-X", "POST", JUGGLER_URL,
                "-H", "Content-Type: application/json",
                "-d", payload,
                "--connect-timeout", "1",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass  # Never crash Kitty


def on_focus_change(boss, window, data):
    """Called by Kitty when a window gains or loses focus."""
    if data.get("focused"):
        _post_event("focus_changed", window.id)


def on_close(boss, window, data):
    """Called by Kitty when a window is closed."""
    _post_event("session_terminated", window.id)
