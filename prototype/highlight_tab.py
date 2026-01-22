#!/usr/bin/env python3
"""Background script to set and reset tab highlight."""
import asyncio
import iterm2
import sys

HIGHLIGHT_DURATION = 5


async def main(connection):
    app = await iterm2.async_get_app(connection)
    uuid = sys.argv[1] if len(sys.argv) > 1 else None

    if not uuid:
        return

    session = app.get_session_by_id(uuid)
    if not session:
        return

    # Set highlight
    change = iterm2.LocalWriteOnlyProfile()
    change.set_tab_color(iterm2.Color(255, 165, 0))
    change.set_use_tab_color(True)
    await session.async_set_profile_properties(change)

    # Wait
    await asyncio.sleep(HIGHLIGHT_DURATION)

    # Reset highlight
    reset = iterm2.LocalWriteOnlyProfile()
    reset.set_use_tab_color(False)
    await session.async_set_profile_properties(reset)


if __name__ == "__main__":
    try:
        iterm2.run_until_complete(main)
    except Exception:
        pass  # Silently fail
