#!/usr/bin/env python3
"""Check if a specific iTerm2 session is currently active (focused)."""
import iterm2
import subprocess
import sys

async def main(connection):
    session_id = sys.argv[1] if len(sys.argv) > 1 else None
    if not session_id:
        sys.exit(1)  # No session ID, assume not active

    app = await iterm2.async_get_app(connection)

    # Check if iTerm2 is the frontmost app
    result = subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to get name of first application process whose frontmost is true'],
        capture_output=True,
        text=True
    )
    frontmost_app = result.stdout.strip()
    if frontmost_app != "iTerm2":
        sys.exit(1)  # iTerm2 not frontmost

    # Check if our session is the current one
    session = app.get_session_by_id(session_id)
    if not session:
        sys.exit(1)  # Session not found

    # Get current active session
    window = app.current_terminal_window
    if window and window.current_tab:
        current_session = window.current_tab.current_session
        if current_session and current_session.session_id == session_id:
            sys.exit(0)  # Session is active!

    sys.exit(1)  # Session not active

if __name__ == "__main__":
    try:
        iterm2.run_until_complete(main)
    except Exception:
        sys.exit(1)
