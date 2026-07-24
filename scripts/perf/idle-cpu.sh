#!/usr/bin/env bash
set -euo pipefail

BIN="${1:?usage: idle-cpu.sh <path-to-Juggler-binary> [--with-bridges]}"
shift || true

PORT="${IDLE_CPU_PORT:-7484}"
THRESHOLD="${IDLE_CPU_THRESHOLD:-0.10}"
SETTLE_SECONDS="${IDLE_CPU_SETTLE:-8}"
WINDOW_SECONDS="${IDLE_CPU_WINDOW:-20}"

ITERM2_ENABLED="NO"
for arg in "$@"; do
    if [[ "$arg" == "--with-bridges" ]]; then ITERM2_ENABLED="YES"; fi
done

LOG="$(mktemp -t juggler-idle-cpu)"
APP_PID=""
cleanup() { [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "Launching Juggler (port=$PORT, iterm2Enabled=$ITERM2_ENABLED)..."
"$BIN" -uiTesting \
    -hasCompletedOnboarding YES \
    -iterm2Enabled "$ITERM2_ENABLED" \
    -kittyEnabled NO \
    -hookPort "$PORT" \
    >"$LOG" 2>&1 &
APP_PID=$!

for _ in $(seq 1 50); do
    if curl -s -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then break; fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "App exited during startup. Log:"; cat "$LOG"; exit 1
    fi
    sleep 0.2
done

if ! curl -s -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then
    echo "App never became ready on port $PORT. Log:"; cat "$LOG"; exit 1
fi

assert_alive() {
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        echo "App exited before/during measurement. Log:"; tail -20 "$LOG"; exit 1
    fi
}

post_hook() {
    curl -s -o /dev/null -X POST "http://localhost:$PORT/hook" \
        -H "Content-Type: application/json" \
        -d "{\"agent\":\"claude-code\",\"event\":\"$2\",\"terminal\":{\"sessionId\":\"$1\",\"cwd\":\"/tmp/$1\"},\"hookInput\":{\"session_id\":\"$1\"}}"
}

echo "Seeding sessions..."
post_hook perf-1 Stop
post_hook perf-2 PreToolUse
post_hook perf-3 PermissionRequest
post_hook perf-4 PreToolUse
post_hook perf-5 Stop

cputime_seconds() {
    local raw
    raw="$(ps -o cputime= -p "$APP_PID" | tr -d ' ')"
    awk -v t="$raw" 'BEGIN {
        n = split(t, a, ":")
        if (n == 3) { printf "%f", a[1]*3600 + a[2]*60 + a[3] }
        else if (n == 2) { printf "%f", a[1]*60 + a[2] }
        else { printf "%f", a[1] }
    }'
}

echo "Settling ${SETTLE_SECONDS}s..."
sleep "$SETTLE_SECONDS"

assert_alive
CPU1="$(cputime_seconds)"
sleep "$WINDOW_SECONDS"
assert_alive
CPU2="$(cputime_seconds)"

CORES="$(awk -v a="$CPU1" -v b="$CPU2" -v w="$WINDOW_SECONDS" 'BEGIN { printf "%.4f", (b-a)/w }')"
echo "Idle CPU over ${WINDOW_SECONDS}s: ${CORES} core(s) (threshold ${THRESHOLD})"

if awk -v c="$CORES" -v t="$THRESHOLD" 'BEGIN { exit !(c < t) }'; then
    echo "PASS"
else
    echo "FAIL: app burned ${CORES} core(s) while idle (>= ${THRESHOLD}). Log tail:"
    tail -20 "$LOG"
    exit 1
fi
