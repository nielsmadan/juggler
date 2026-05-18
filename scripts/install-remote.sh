#!/usr/bin/env bash
# Juggler remote hook installer.
# Detects which coding agents are present on this host (Claude Code, Codex,
# OpenCode) and installs Juggler integration for each. Intended to be piped
# from curl on a machine you ssh to:
#
#   ssh user@remote 'curl -fsSL https://raw.githubusercontent.com/nielsmadan/juggler/v1.4.2/scripts/install-remote.sh | bash'
#
# The SettingsView SSH tab pins the curl URL to a release tag; this script's
# default BASE matches that tag so the two halves stay in sync. Bump on release.

set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BASE="${JUGGLER_BASE_URL:-https://raw.githubusercontent.com/nielsmadan/juggler/v1.4.2/juggler/Resources}"

installed_any=0
failed_any=0

# Each agent installs in its own subshell. `set -e` inside the subshell aborts
# that agent's block on the first error, but the `if !` keeps the failure from
# aborting the whole script — so one agent failing doesn't block the others.

# Claude Code
if [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1; then
    echo "Detected Claude Code — installing hooks..."
    if (
        set -e
        curl -fsSL "$BASE/hooks/install.sh" -o "$TMP/cc-install.sh"
        curl -fsSL "$BASE/hooks/notify.sh"  -o "$TMP/notify.sh"
        chmod +x "$TMP/cc-install.sh" "$TMP/notify.sh"
        bash "$TMP/cc-install.sh"
    ); then
        installed_any=1
    else
        echo "  Claude Code install failed — skipping." >&2
        failed_any=1
    fi
fi

# Codex
if [ -d "$HOME/.codex" ] || command -v codex >/dev/null 2>&1; then
    echo "Detected Codex — installing hooks..."
    if (
        set -e
        curl -fsSL "$BASE/codex-hooks/codex-install.sh" -o "$TMP/codex-install.sh"
        curl -fsSL "$BASE/codex-hooks/codex-notify.sh"   -o "$TMP/codex-notify.sh"
        chmod +x "$TMP/codex-install.sh" "$TMP/codex-notify.sh"
        bash "$TMP/codex-install.sh"
    ); then
        installed_any=1
    else
        echo "  Codex install failed — skipping." >&2
        failed_any=1
    fi
fi

# OpenCode
opencode_dir="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
if [ -d "$opencode_dir" ] || command -v opencode >/dev/null 2>&1; then
    echo "Detected OpenCode — installing plugin..."
    if (
        set -e
        plugin_path="$opencode_dir/plugins/juggler-opencode.ts"
        mkdir -p "$opencode_dir/plugins"
        if [ -f "$plugin_path" ]; then
            cp "$plugin_path" "$plugin_path.juggler-backup"
        fi
        curl -fsSL "$BASE/opencode-plugin/juggler-opencode.txt" -o "$plugin_path"
        echo "  Plugin installed: $plugin_path"
    ); then
        installed_any=1
    else
        echo "  OpenCode install failed — skipping." >&2
        failed_any=1
    fi
fi

if [ "$installed_any" -eq 0 ]; then
    if [ "$failed_any" -eq 1 ]; then
        echo "All detected agents failed to install." >&2
        exit 1
    fi
    echo "No supported coding agents detected on this host."
    echo "Looked for: ~/.claude, ~/.codex, $opencode_dir (or the agent CLIs on \$PATH)."
    echo "Install one of them, then re-run this script."
    exit 1
fi

if [ "$failed_any" -eq 1 ]; then
    echo "Done (with some failures — see above)."
else
    echo "Done."
fi
