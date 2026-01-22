# Daemon Crash: Python 3.9+ Type Hint Syntax on Python 3.8

**Date:** 2026-02-07
**Status:** Resolved
**Affected Area:** `Juggler/Resources/iterm2_daemon.py`

## Problem
The iTerm2 daemon crashes immediately at class definition time, breaking all iTerm2 integration: highlighting, pane activation, and focus monitoring.

## Symptoms
- Pane/tab bar highlighting stops working entirely
- Console floods with `[WARNING] [daemon] Stale connection in getSessionInfo, attempting recovery...` and `daemonNotRunning`
- Python traceback: `TypeError: 'type' object is not subscriptable` at line 126 (`dict[str, Any]`)

## Root Cause
Commit `a56b036` ("fix: python best practices issues") changed type hints from `typing.Dict`/`typing.List` to built-in generics (`dict[str, Any]`, `list[...]`). This syntax requires Python 3.9+.

However, `ITerm2Bridge.swift` picks iTerm2's bundled Python using **lexicographic** sort (`contents.sorted().reversed()`), which selects `3.8.19` before `3.14.0` or `3.10.19`. The daemon runs on Python 3.8, where `dict[str, Any]` fails at class definition time.

## Solution
Added `from __future__ import annotations` at the top of `iterm2_daemon.py`. This enables PEP 563 postponed evaluation of annotations, making all type hints string-based so they're never evaluated at runtime. Works on Python 3.7+.

## Prevention
- The iTerm2 daemon must support Python 3.7+ since iTerm2 bundles multiple Python versions and the version picker uses lexicographic (not semantic) sorting
- Always include `from __future__ import annotations` in `iterm2_daemon.py` to safely use modern type hint syntax
- When applying Python linting/modernization to this file, remember it doesn't run under the system Python - it runs under iTerm2's bundled Python
- Test the daemon after any Python syntax changes by checking the console for `TypeError` on startup

## Related
- iTerm2 Python environments live in `~/Library/Application Support/iTerm2/iterm2env*/versions/`
- Version picker: `ITerm2Bridge.swift:54` - `contents.sorted().reversed()`
