# Existing hooklinesinker version selection

Use the isolated matrix for every installer/version-selection change. Add the VM smoke test
before a release that changes bundled HLS or Juggler's registration/startup behavior. Start with
the authenticated VM from the [main procedure](README.md); this check does not repeat onboarding.

The expected behavior is to upgrade an older compatible helper and retain an equal or newer
compatible helper, preserving other consumers in every case. A version-bumped fixture tests
selection and integration with the existing protocol, not compatibility with future HLS code.

## Prepare exact artifacts

Run from the Juggler repository root. Use the helper inside the exact Juggler app under test,
after the artifact/signature checks in the main procedure. Supply a local HLS source checkout
and explicit revisions; the pinned source revision is in `scripts/hooklinesinker.json` for a
current-checkout test. For a published Juggler release, read that file at the release's commit.
The [recorded release run](runs/2026-09-18-hls-version-selection.md) provides a known fixture set.

```bash
hls_work="$PWD/build/hls-selection-$(date +%Y%m%d-%H%M%S)"
hls_repo="<absolute-path-to-hooklinesinker-checkout>"
hls_older_revision="<older-protocol-compatible-tag-or-commit>"
hls_bundled_revision="<source-revision-for-bundled-helper>"
hls_newer_version="<higher-stable-major.minor.patch-version>"
hls_bundled="<absolute-path-to-tested-Juggler.app>/Contents/MacOS/hooklinesinker"
mkdir -p "$hls_work/older" "$hls_work/newer" "$hls_work/shared"
git -C "$hls_repo" rev-parse "$hls_older_revision^{commit}" "$hls_bundled_revision^{commit}"
git -C "$hls_repo" archive "$hls_older_revision" | tar -x -C "$hls_work/older"
git -C "$hls_repo" archive "$hls_bundled_revision" | tar -x -C "$hls_work/newer"
"$hls_bundled" version --json
```

Record the resolved commits and selected fixture version. The following changes exactly the
HLS package version in the temporary newer source's manifest and lockfile. It fails if the
expected package layout differs. The source checkout remains untouched.

```bash
python3 - "$hls_work/newer" "$hls_newer_version" <<'PY'
from pathlib import Path
import re
import sys

root, version = Path(sys.argv[1]), sys.argv[2]
assert re.fullmatch(r"\d+\.\d+\.\d+", version), "Use a stable release version"
before = {path.relative_to(root): path.read_bytes() for path in root.rglob("*") if path.is_file()}
for filename, section in (("Cargo.toml", r"\[package\]"), ("Cargo.lock", r"\[\[package\]\]")):
    path = root / filename
    source = path.read_text()
    pattern = rf'({section}\nname = "hooklinesinker"\nversion = ")[^"]+("\n)'
    updated, count = re.subn(pattern, lambda match: match[1] + version + match[2], source)
    assert count == 1 and updated != source, f"Unexpected package/version in {filename}"
    path.write_text(updated)
changed = {str(path) for path, contents in before.items() if (root / path).read_bytes() != contents}
assert changed == {"Cargo.toml", "Cargo.lock"}, changed
print("Only Cargo.toml and Cargo.lock package versions changed")
PY

cargo --version
cargo build --release --locked --manifest-path "$hls_work/older/Cargo.toml" --target-dir "$hls_work/target-older"
cp "$hls_work/target-older/release/hooklinesinker" "$hls_work/shared/hls-older"
cargo build --release --locked --manifest-path "$hls_work/newer/Cargo.toml" --target-dir "$hls_work/target-newer"
cp "$hls_work/target-newer/release/hooklinesinker" "$hls_work/shared/hls-newer"
```

These fixture binaries target the host architecture, which must match the Tart guest. Keep
Cargo output outside the archived sources. Save Cargo version, source revisions, artifact
checksums and the fact that the newer version is synthetic in the run record.

## Run the isolated matrix

```bash
python3 scripts/tests/hls_version_selection.py matrix \
  --bundled "$hls_bundled" \
  --older "$hls_work/shared/hls-older" \
  --newer "$hls_work/shared/hls-newer" \
  --output "$hls_work/matrix"
```

The output directory must not exist. Each case creates fresh XDG data/state directories and
runs only `install`, `version`, and `consumers`. The script checks `older < bundled < newer`,
protocol equality, active version/checksum, complete preservation of the existing consumer,
and Juggler's registration/sink. Equal/newer cases also preserve inode, modification time and
symlink target. A failure exits nonzero. Once cases begin, failures leave an `INCOMPLETE`
report; preflight failures do not create a report or overwrite an existing output directory.

Read all three `PASS` lines, the exit code, and `matrix/matrix-results.json`. The JSON contains
no absolute paths or session identifiers. Do not run `hooks install`, `hooks uninstall`, or
`uninstall` on the host: XDG isolation does not relocate agent configuration.

## Retained-newer VM smoke test

Quit Claude and Juggler in the source guest, shut it down, and clone it following the main
procedure. Run only the disposable clone. Keep its name in `$vm`; do not use the original name.
Copy the read-only inspection helper into the fixture share before booting:

```bash
cp scripts/tests/hls_version_selection.py scripts/tests/juggler_vm_bridge.py \
  scripts/tests/juggler_vm_ui.applescript "$hls_work/shared/"
tart run --capture-system-keys --dir=shared:"$hls_work/shared":ro "$vm"
```

Run subsequent commands in another host shell with the same `$vm` and `$hls_work` values.
The guest may reopen Juggler at login; explicitly quit it before changing HLS. All commands
in this section that register/unregister consumers execute inside the disposable guest.

```bash
tart exec "$vm" /usr/bin/osascript -e 'tell application "Juggler" to quit'
tart exec "$vm" '/Volumes/My Shared Files/shared/hls-newer' install --consumer preexisting-tool
tart exec "$vm" /bin/sh -c '"$HOME/.local/share/hooklinesinker/bin/hooklinesinker" uninstall --consumer juggler'
```

The preexisting consumer must be installed successfully before removing Juggler's registration:
it keeps the shared hooks installed. Stop if either command fails. This clone has inherited
onboarding/preferences, so it tests startup registration with a newer helper already present.

Resolve a guest Python 3 interpreter using the main procedure's iTerm2 runtime discovery,
and store its full guest path in host variable `$guest_python`. The inspection helper needs
only Python's standard library; it does not connect to iTerm2 or read authentication material.

```bash
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/hls_version_selection.py' inspect > "$hls_work/vm-before.json"
tart exec "$vm" /usr/bin/open -a /Applications/Juggler.app
```

Wait until Juggler is responsive and its integrations have finished loading, then:

```bash
tart exec "$vm" "$guest_python" '/Volumes/My Shared Files/shared/hls_version_selection.py' inspect > "$hls_work/vm-after.json"
python3 - "$hls_work/vm-before.json" "$hls_work/vm-after.json" <<'PY'
import json
import sys

before, after = (json.load(open(path)) for path in sys.argv[1:])
assert before["jugglerRegistered"] is False
assert after["jugglerRegistered"] and after["jugglerSinkMatches"]
assert len(before["otherConsumerDigests"]) >= 1
assert len(after["consumerDigests"]) == len(before["consumerDigests"]) + 1
for field in ("version", "binary", "otherConsumerDigests", "hooks", "settingsSha256"):
    assert before[field] == after[field], field
assert after["hooks"]["state"] == "installed"
assert after["hooks"]["count"] == 11
assert after["settingsSha256"] is not None
print("PASS: newer helper and shared configuration retained; Juggler registered")
PY
```

Compare the snapshot version and binary checksum with the matrix's newer fixture. Snapshots
contain hashes of configuration/registration records instead of commands, home paths or
consumer names. Hashes compare within this guest; they are not portable across user homes.

Using the main procedure's authenticated iTerm2 driver, start Claude in the test workspace and
confirm one idle row. Submit this prompt, sending Return separately from the text:

> Use Bash to run sleep 8 in the foreground, then reply with exactly vm-newer-hls-ok.
> Do not run it in the background. Do not read or modify any files.

Observe Juggler's working → idle transition and the exact reply, plus HLS events
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop` with stable session/terminal identity.
Capture another `inspect` snapshot and compare it with `vm-after.json`; binary, consumers,
hooks and settings must still match. Send `/exit` and verify an empty HLS ledger, no Claude
process and Juggler's empty state. Use the main procedure for those UI/ledger assertions.

Shut down and delete only the disposable clone. Restore the original VM to its prior running
or stopped state; if it was running, verify its original HLS version/checksum and registration.
Record results in `runs/` with sanitized evidence. Keep fixture sources and working directories
under ignored `build/`.
