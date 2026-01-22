#!/usr/bin/env python3
"""Background script to reset tab color after a delay."""
import asyncio
import iterm2
import sys

DELAY_SECONDS = 5


async def main(connection):
    await asyncio.sleep(DELAY_SECONDS)

    app = await iterm2.async_get_app(connection)
    uuid = sys.argv[1] if len(sys.argv) > 1 else None

    if not uuid:
        return

    session = app.get_session_by_id(uuid)
    if session:
        reset = iterm2.LocalWriteOnlyProfile()
        reset.set_use_tab_color(False)
        await session.async_set_profile_properties(reset)


if __name__ == "__main__":
    try:
        iterm2.run_until_complete(main)
    except Exception:
        pass  # Silently fail - tab color reset is not critical
