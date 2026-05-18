#!/usr/bin/env bash
# Juggler remote hook installer.
# Fetches install.sh + notify.sh from the Juggler repo, runs the installer,
# and cleans up. Intended to be piped from curl on a machine you ssh to:
#
#   ssh user@remote 'curl -fsSL https://raw.githubusercontent.com/nielsmadan/juggler/v1.4.1/scripts/install-remote.sh | bash'
#
# The SettingsView SSH tab pins the curl URL to a release tag; this script's
# default BASE matches that tag so the two halves stay in sync. Bump on release.

set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BASE="${JUGGLER_HOOKS_BASE_URL:-https://raw.githubusercontent.com/nielsmadan/juggler/v1.4.1/juggler/Resources/hooks}"

echo "Fetching Juggler hook scripts from $BASE..."
curl -fsSL "$BASE/install.sh" -o "$TMP/install.sh"
curl -fsSL "$BASE/notify.sh"  -o "$TMP/notify.sh"

chmod +x "$TMP/install.sh" "$TMP/notify.sh"
bash "$TMP/install.sh"
