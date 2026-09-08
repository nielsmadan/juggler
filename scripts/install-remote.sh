#!/usr/bin/env bash
# Juggler remote hook installer.
# Installs hooklinesinker — the shared status binary Juggler bundles — on a host you ssh
# to, and registers Juggler's hooks for whichever coding agents live there (Claude Code,
# Codex, OpenCode, Pi). Intended to be piped from curl:
#
#   curl -fsSL https://raw.githubusercontent.com/nielsmadan/juggler/<revision>/scripts/install-remote.sh |
#       JUGGLER_SINK=http://127.0.0.1:7483/hook bash
#
# `just release` advances the default revision to an immutable release-preparation commit.
#
# The remote host reaches Juggler's HTTP sink over your ssh tunnel, so forward the port:
#   ssh -R 7483:localhost:7483 <host>

set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REVISION="${JUGGLER_REVISION:-d8b864f579e10fe0680a27b4b05324ebdc4e9b76}"
HLS_VERSION="${HOOKLINESINKER_VERSION:-v1.0.0}"
HLS_BASE="${HOOKLINESINKER_BASE_URL:-https://github.com/nielsmadan/hooklinesinker/releases/download/$HLS_VERSION}"
SINK="${JUGGLER_SINK:-http://127.0.0.1:7483/hook}"

echo "Juggler remote installer (revision $REVISION)"

case "$(uname -s)/$(uname -m)" in
    Darwin/arm64 | Darwin/x86_64) ARTIFACT="hooklinesinker-macos-universal" ;;
    Linux/aarch64 | Linux/arm64) ARTIFACT="hooklinesinker-linux-aarch64" ;;
    Linux/x86_64) ARTIFACT="hooklinesinker-linux-x86_64" ;;
    *)
        echo "No hooklinesinker build for $(uname -s)/$(uname -m)." >&2
        echo "Supported: macOS (arm64, x86_64) and Linux (aarch64, x86_64)." >&2
        exit 1
        ;;
esac

if command -v shasum >/dev/null 2>&1; then
    sha256() { shasum -a 256 "$@"; }
elif command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$@"; }
else
    echo "Neither shasum nor sha256sum is available — cannot verify the download." >&2
    exit 1
fi

echo "Downloading $ARTIFACT ($HLS_VERSION)..."
if ! curl -fsSL "$HLS_BASE/$ARTIFACT" -o "$TMP/hooklinesinker"; then
    echo "Could not download $HLS_BASE/$ARTIFACT" >&2
    exit 1
fi
if ! curl -fsSL "$HLS_BASE/SHA256SUMS" -o "$TMP/SHA256SUMS"; then
    echo "Could not download $HLS_BASE/SHA256SUMS — refusing to run an unverified binary" >&2
    exit 1
fi

EXPECTED="${HOOKLINESINKER_SHA256:-$(awk -v a="$ARTIFACT" '$2 == a || $2 == "*"a {print $1}' "$TMP/SHA256SUMS")}"
ACTUAL="$(sha256 "$TMP/hooklinesinker" | cut -d' ' -f1)"
if [ -z "$EXPECTED" ]; then
    echo "SHA256SUMS has no entry for $ARTIFACT — refusing to run an unverified binary" >&2
    exit 1
fi
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Checksum mismatch for $ARTIFACT:" >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $ACTUAL" >&2
    exit 1
fi
chmod +x "$TMP/hooklinesinker"

echo "Registering the juggler consumer (sink $SINK)..."
"$TMP/hooklinesinker" install --consumer juggler --sink "$SINK"

# The install above promoted the binary; run the promoted copy from here on, because that
# is the path the hooks it writes will point at.
HLS="${XDG_DATA_HOME:-$HOME/.local/share}/hooklinesinker/bin/hooklinesinker"
[ -x "$HLS" ] || HLS="$TMP/hooklinesinker"

installed_any=0
failed_any=0
codex_seen=0

install_agent() {
    agent="$1"
    echo "Detected $agent — installing hooks..."
    if "$HLS" hooks install --agent "$agent"; then
        installed_any=1
    else
        echo "  $agent hook install failed — skipping." >&2
        failed_any=1
    fi
}

if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
    install_agent claude
fi

if [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
    install_agent codex
    codex_seen=1
fi

opencode_dir="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
if [ -d "$opencode_dir" ] || command -v opencode >/dev/null 2>&1; then
    install_agent opencode
fi

pi_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
if [ -d "$pi_dir" ] || command -v pi >/dev/null 2>&1; then
    install_agent pi
fi

if [ "$installed_any" -eq 0 ]; then
    if [ "$failed_any" -eq 1 ]; then
        echo "All detected agents failed to install." >&2
        exit 1
    fi
    echo "No supported coding agents detected on this host."
    echo "Looked for: ~/.claude, ~/.codex, $opencode_dir, $pi_dir (or the agent CLIs on \$PATH)."
    echo "Install one of them, then re-run this script."
    exit 1
fi

if [ "$codex_seen" -eq 1 ]; then
    echo ""
    echo "Codex needs two more steps that only you can take on this host:"
    echo "  1. set [features] hooks = true in ~/.codex/config.toml"
    echo "  2. run /hooks inside Codex and approve the hooklinesinker entries"
    echo "Neither is written for you here: trust records are the host application's business,"
    echo "and hooklinesinker never edits config.toml."
fi

if [ "$failed_any" -eq 1 ]; then
    echo "Done (with some failures — see above)."
else
    echo "Done."
fi
