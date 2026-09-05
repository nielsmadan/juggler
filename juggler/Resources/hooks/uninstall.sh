#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/integration_cleanup.py"
if [ ! -f "$CLEANUP_SCRIPT" ]; then
    CLEANUP_SCRIPT="$SCRIPT_DIR/../integration_cleanup.py"
fi

exec python3 -B "$CLEANUP_SCRIPT" "$@"
