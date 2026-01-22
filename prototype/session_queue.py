#!/usr/bin/env python3
"""Centralized session queue management with atomic file locking."""

import fcntl
import sys
import os
from pathlib import Path
from typing import Callable

QUEUE_FILE = Path.home() / ".claude_session_queue"


def extract_uuid(session_id: str) -> str:
    """Extract UUID from 'w0t0p0:UUID' format."""
    return session_id.split(':', 1)[1] if ':' in session_id else session_id


def _atomic_modify(operation: Callable[[list[str]], None]) -> list[str]:
    """
    Perform an atomic read-modify-write operation on the queue.
    Lock is held for the ENTIRE operation to prevent race conditions.
    """
    # Ensure file exists
    QUEUE_FILE.touch(exist_ok=True)

    with open(QUEUE_FILE, 'r+') as f:
        # Acquire EXCLUSIVE lock - blocks until available
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            # Read current state
            content = f.read()
            sessions = [l for l in content.strip().split('\n') if l.strip()]

            # Apply the modification
            operation(sessions)

            # Write back atomically
            f.seek(0)
            f.truncate()
            f.write('\n'.join(sessions) + '\n' if sessions else '')
            f.flush()
            os.fsync(f.fileno())  # Ensure write hits disk

            return sessions
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def _atomic_read() -> list[str]:
    """Read queue with shared lock."""
    if not QUEUE_FILE.exists():
        return []
    with open(QUEUE_FILE, 'r') as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_SH)
        try:
            content = f.read()
            return [l for l in content.strip().split('\n') if l.strip()]
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def add(session_id: str):
    """Add session to queue if not present (atomic)."""
    def op(sessions):
        if session_id not in sessions:
            sessions.append(session_id)
    _atomic_modify(op)


def remove(session_id: str):
    """Remove session from queue (atomic)."""
    def op(sessions):
        sessions[:] = [s for s in sessions if s != session_id]
    _atomic_modify(op)


def first() -> str | None:
    """Get first session in queue."""
    sessions = _atomic_read()
    return sessions[0] if sessions else None


def get_next(current_session: str = None) -> str | None:
    """Get next session, skipping current."""
    sessions = _atomic_read()
    for s in sessions:
        if not current_session or extract_uuid(s) != extract_uuid(current_session):
            return s
    return None


def rotate(session_id: str):
    """Move session to end of queue (atomic)."""
    def op(sessions):
        if session_id in sessions:
            sessions.remove(session_id)
            sessions.append(session_id)
    _atomic_modify(op)


def count() -> int:
    """Return number of sessions in queue."""
    return len(_atomic_read())


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    session_id = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("ITERM_SESSION_ID")

    if cmd == "add" and session_id:
        add(session_id)
    elif cmd == "remove" and session_id:
        remove(session_id)
    elif cmd == "first":
        result = first()
        if result:
            print(result)
        else:
            sys.exit(1)
    elif cmd == "next":
        current = sys.argv[2] if len(sys.argv) > 2 else None
        result = get_next(current)
        if result:
            print(result)
        else:
            sys.exit(1)
    elif cmd == "rotate" and session_id:
        rotate(session_id)
    elif cmd == "count":
        print(count())
    elif cmd == "list":
        for s in _atomic_read():
            print(s)
    else:
        print("Usage: session_queue.py <add|remove|first|next|rotate|count|list> [session_id]")
        sys.exit(1)
