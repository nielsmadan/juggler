#!/usr/bin/env python3
import subprocess
import sys
import os


def extract_uuid(session_id: str) -> str:
    """Extract UUID from 'w0t0p0:UUID' format."""
    return session_id.split(':', 1)[1] if ':' in session_id else session_id


def activate_session_applescript(uuid: str):
    """Use AppleScript for fast session activation."""
    # AppleScript to activate specific session by UUID
    script = f'''
    tell application "iTerm2"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if unique ID of s is "{uuid}" then
                        select t
                        tell w to select s
                        return
                    end if
                end repeat
            end repeat
        end repeat
    end tell
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True)


def set_highlight_async(uuid: str):
    """Spawn background process to set and reset highlight."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    highlight_script = os.path.join(script_dir, "highlight_tab.py")
    subprocess.Popen(
        [sys.executable, highlight_script, uuid],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True
    )


if __name__ == "__main__":
    session_id = sys.argv[1] if len(sys.argv) > 1 else None

    if not session_id:
        subprocess.run(["osascript", "-e", 'tell application "iTerm2" to activate'], capture_output=True)
        sys.exit(0)

    uuid = extract_uuid(session_id)

    # Fast activation via AppleScript
    activate_session_applescript(uuid)

    # Async highlight via Python API (background)
    set_highlight_async(uuid)
