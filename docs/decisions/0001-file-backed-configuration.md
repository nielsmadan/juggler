# File-Backed Configuration Design

**Date:** 2026-08-30
**Status:** Accepted; implementation pending
**Repositories:** Juggler and ShortcutKit

## Summary

Juggler can use a human-editable TOML file as the authoritative source for its
portable settings and ShortcutKit overrides. Framework-owned and operational
preferences remain outside this configuration boundary. The file lives at
`$XDG_CONFIG_HOME/juggler/config.toml`, falling back to
`~/.config/juggler/config.toml`.

File presence selects the backend. When the file exists, Juggler does not read
configuration values from `UserDefaults` or other macOS preference storage.
Missing keys use Juggler's compiled defaults. When the file does not exist,
Juggler retains its current macOS-backed behavior. The two sources are never
merged.

The file stores explicit overrides rather than a dump of every effective value.
It supports automatic reload, preserves comments and unknown content, and is
shared safely by Juggler's settings store and ShortcutKit's `FileStore`.

## Goals

- Store every durable portable Juggler choice, including ordinary settings,
  terminal integration enablement, agent behavior, ShortcutKit preferences,
  and shortcut overrides.
- Make source selection deterministic and prevent stale macOS preferences from
  leaking into file mode.
- Keep the generated file sparse and useful for dotfile management.
- Preserve hand-written comments, formatting, and unknown content during UI
  edits.
- Reload valid external edits without restarting Juggler.
- Reject a partially invalid candidate as one unit and keep a usable runtime
  configuration.
- Report actionable configuration errors with a path and source location when
  available.

## Non-goals

- Storing runtime or historical state in the configuration file.
- Synchronizing or merging the file with macOS preferences.
- Turning ShortcutKit into a general application-settings framework.
- Polling the file on a timer.
- Storing secrets or machine-detected integration status.
- Supporting another configuration format in Juggler.
- Replacing or mirroring Sparkle's framework-owned update preferences.

## Source Selection

The resolved path is:

1. `$XDG_CONFIG_HOME/juggler/config.toml` when `XDG_CONFIG_HOME` is a usable
   absolute path.
2. `~/.config/juggler/config.toml` otherwise.

Presence is resolved component by component without following away the logical
path. A missing ordinary component means the file is absent. A broken symlink,
directory, FIFO, unreadable file, symlink cycle, invalid UTF-8 file, or other
non-regular target is present but invalid. Replacing a symlinked configuration
updates its referent; uninstall removes the logical symlink rather than its
referent.

Startup resolves configuration before normal services, terminal bridges,
hotkeys, and the status UI start.

| Startup state | Active source | Effective values |
| --- | --- | --- |
| File absent | macOS preferences | Persisted macOS values over compiled defaults |
| File present and valid | TOML file | Explicit file values over compiled defaults |
| File present but invalid or unreadable | Invalid-file mode | Compiled defaults only |

File mode never consults macOS preference values for file-backed configuration,
including for keys omitted from the file. Invalid-file mode follows the same
rule; it must not silently resurrect a stale configuration value from
`UserDefaults`.

The active source is fixed for the session except after a successful in-app
export. A file created manually while Juggler is already using macOS preferences
takes effect on the next launch. A file removed during file mode leaves the last
valid snapshot active for the rest of the session. On the next launch, its
absence selects macOS preferences again.

Export does not clear macOS preferences. File-backed macOS configuration values
remain dormant while the file exists and become active again only after the
file is removed and Juggler is restarted. Operational and framework-owned
preferences remain active in every mode.

## Setting Classification

The file contains portable durable user intent:

- General application behavior, Launch at Login, and Dock visibility.
- Notification choices.
- Stats visibility and appearance, but not accumulated stats.
- Queue order, cycling behavior, and control-bar behavior toggles.
- Terminal and agent enablement and agent-specific behavior choices.
- Session-list and terminal highlighting.
- Beacon enablement and appearance.
- Shortcut helper and ShortcutKit hint preferences.
- All ShortcutKit binding overrides.
- Verbose logging.

The following remain operational state in macOS storage or memory:

- Onboarding completion and dismissed one-time hints.
- Main-window geometry.
- Daily busy-time history.
- Current sessions and transient selection state.
- Logs.
- Permission, installation, and integration-detection results.
- Sparkle update preferences and framework bookkeeping.
- Internal framework preferences that are not user-facing settings.

Operational state remains available in file mode. It is not a configuration
fallback and does not affect the effective value of any file-backed setting.
Sparkle remains the sole owner of its preferences in every backend, so update
choices are neither exported nor read through Juggler's configuration model.

## Sparse Overrides

Compiled defaults have one canonical definition in `JugglerSettings`. A setting
is normally written only while its value differs from that default. Returning a
setting to its default through Juggler removes its assignment from the file.

An explicit default value written by hand is a pin and remains in place until
that setting is changed through Juggler. Export from macOS preferences includes
effective non-default Juggler settings and ShortcutKit's existing explicit
overrides; it does not attempt to preserve macOS assignments that equal a
compiled default.

Legacy highlight and beacon durations accept any finite positive value even
though the UI offers a preset list. Legacy RGB components are clamped to
`0...255` with a warning; non-finite components use the compiled color. A
persisted Launch at Login intent wins over observed service state, and service
state is consulted only when the legacy preference is absent.

The file has no schema-version counter. Renames and representation changes use
stable keys and append-only, idempotent, content-detecting migrations.

## TOML Schema

Regular setting IDs are stable, lower-case, kebab-case paths. ShortcutKit keeps
the existing case-sensitive context and action persistence IDs. Colors use
`#RRGGBB` strings in sRGB.

The regular settings and compiled defaults are:

| Path | Type or allowed values | Default |
| --- | --- | --- |
| `general.launch-at-login` | Boolean | `false` |
| `general.show-in-dock` | Boolean | `true` |
| `general.quit-on-monitor-close` | Boolean | `false` |
| `general.session-title-mode` | `tab-title`, `window-title`, `window-and-tab-title`, `folder-name`, `parent-and-folder-name` | `parent-and-folder-name` |
| `notifications.on-idle` | Boolean | `true` |
| `notifications.on-permission` | Boolean | `true` |
| `notifications.play-sound` | Boolean | `false` |
| `stats.enabled` | Boolean | `true` |
| `stats.use-cycling-colors` | Boolean | `true` |
| `stats.bar-color` | `#RRGGBB` | `#FFA500` |
| `cycling.queue-order` | `fair`, `prio`, `static`, `grouped` | `fair` |
| `cycling.go-to-next-on-backburner` | Boolean | `true` |
| `cycling.auto-advance-on-busy` | Boolean | `false` |
| `cycling.auto-restart-on-idle` | Boolean | `false` |
| `cycling.prioritize-permission-sessions` | Boolean | `false` |
| `integrations.terminals.iterm2-enabled` | Boolean | `true` |
| `integrations.terminals.kitty-enabled` | Boolean | `false` |
| `integrations.terminals.wezterm-enabled` | Boolean | `false` |
| `integrations.agents.codex-ignore-permission-events` | Boolean | `false` |
| `highlighting.on-hotkey` | Boolean | `true` |
| `highlighting.on-session-select` | Boolean | `true` |
| `highlighting.on-notification` | Boolean | `true` |
| `highlighting.session-list-use-cycling-colors` | Boolean | `true` |
| `highlighting.terminal-use-cycling-colors` | Boolean | `true` |
| `highlighting.tab-enabled` | Boolean | `true` |
| `highlighting.tab-duration` | `1`, `2`, `3`, or `5` seconds | `2` |
| `highlighting.tab-color` | `#RRGGBB` | `#FFA500` |
| `highlighting.pane-enabled` | Boolean | `true` |
| `highlighting.pane-duration` | `1`, `2`, `3`, or `5` seconds | `1` |
| `highlighting.pane-color` | `#RRGGBB` | `#FFA500` |
| `beacon.enabled` | Boolean | `true` |
| `beacon.position` | `center`, `top-left`, `top-right`, `bottom-left`, `bottom-right` | `center` |
| `beacon.relative-to` | `screen`, `active-window` | `screen` |
| `beacon.size` | `xs`, `s`, `m`, `l`, `xl` | `m` |
| `beacon.duration` | `0.5`, `1`, `1.5`, `2`, or `3` seconds | `1.5` |
| `shortcut-ui.show-helper` | Boolean | `true` |
| `logging.verbose` | Boolean | `false` |

ShortcutKit owns `[shortcuts.<context-id>]` and
`[shortcuts.preferences]`. Its existing binding syntax and preference keys are
unchanged. A representative file is:

```toml
# Juggler configuration. Missing values use application defaults.

[general]
show-in-dock = false
session-title-mode = "parent-and-folder-name"

[stats]
bar-color = "#4D9BFF"

[integrations.terminals]
kitty-enabled = true

[shortcuts.global]
cycleForward = "shift+cmd+j"

[shortcuts.preferences]
hints-enabled = false
```

## Ownership and Components

### Juggler

`JugglerSettings` is the `@Observable`, typed, main-actor model for effective
configuration. Views and ordinary consumers observe it instead of reading
`@AppStorage` or `UserDefaults` directly.

`JugglerSettingsStore` has two implementations:

- `UserDefaultsSettingsStore` reads and writes the current macOS preference
  representation.
- `TOMLSettingsStore` reads and patches regular setting assignments through the
  shared TOML file.

`ConfigurationController` owns path resolution, startup selection, export,
opening and revealing the file, the directory watcher, reload staging, current
status, warnings, and errors.

`ConfigurationWriteCoordinator` is the only file-mode writer. Settings edits,
shortcut edits, migrations, and export all read one latest snapshot, validate
and migrate both schemas, apply their path-level changes, validate the complete
candidate, and atomically commit it once. `TOMLFile` serializes the underlying
byte transaction; the coordinator supplies Juggler's whole-application
validity.

`ConfigAwareShortcutStore` is a Juggler-owned `ShortcutBindingsStore` adapter.
It delegates to ShortcutKit's `UserDefaultsStore` or `FileStore` according to
the same source decision as ordinary settings. This keeps one
`ShortcutRegistry` instance alive across export and reload.

`SettingsReconciler` compares the previous and new settings and brings external
systems into line. It owns side effects such as Launch at Login, activation
policy, terminal bridge lifecycle, and agent behavior. Pure consumers read
`JugglerSettings` directly. Sparkle continues to own its update preferences
outside the configuration model.

### ShortcutKit

ShortcutKit Core adds a public, lossless `TOMLFile` primitive. One shared
instance is used by Juggler's `TOMLSettingsStore` and ShortcutKit's `FileStore`.
It provides immutable, `Sendable` snapshots containing source text and a content
revision, serializes in-process writes, patches the most recent valid source,
writes atomically, and returns structured diagnostics.

`FileStore` gains an additive initializer accepting `TOMLFile` and a way to
decode `RawState` from a supplied snapshot. The latter lets Juggler validate
settings and shortcuts from exactly the same bytes. Existing URL-based TOML and
JSON APIs remain supported. ShortcutKit continues to own shortcut encoding,
decoding, overrides, preferences, and migrations.

ShortcutKit does not own Juggler's setting schema, source-selection policy,
watcher, application effects, or configuration UI.

## Startup and Runtime Flows

### Valid file at startup

1. Resolve and read one coherent file snapshot.
2. Parse TOML syntax and run migrations in memory.
3. Decode and validate regular settings and shortcut state from that snapshot.
4. Build effective settings from compiled defaults plus explicit file values.
5. Initialize the settings model and shortcut store from the staged candidate.
6. Start normal app services and reconcile external effects.
7. Start watching the containing directory.

The entire candidate is accepted or rejected. A valid settings section cannot
be applied alongside an invalid shortcuts section, or vice versa.

### Invalid file at startup

Juggler shows a modal alert before normal services start. The alert contains the
resolved path and, when available, the line, column, full setting or shortcut
path, offending value, and expected type or allowed values.

The actions are:

- **Open File and Continue**: open the file in its default editor and start with
  compiled defaults.
- **Continue with Defaults**: start with compiled defaults without opening it.
- **Quit Juggler**: terminate before normal startup.

Continuing enters invalid-file mode. All file-backed settings and shortcut
editors are read-only so Juggler cannot overwrite or partially repair the file.
Opening and revealing the file remain available. The watcher stays active; once
the file is valid, Juggler applies it as one candidate and re-enables editing.

### Export

1. Flush any pending ShortcutKit save. A failure stops export.
2. Capture effective Juggler settings and ShortcutKit explicit overrides.
3. Create the parent directory if needed.
4. Refuse to overwrite a file that appeared after startup.
5. Write a canonical, commented TOML file atomically.
6. Switch both stores to the new file snapshot.
7. Start the watcher and update the Configuration UI.

A failed export leaves both active stores unchanged. A successful export is the
only mid-session transition from macOS preferences to file mode.

### UI edit in file mode

The shared TOML layer reads the latest file content, verifies that it is valid,
and patches only the affected assignment. It preserves all untouched bytes. If
the current disk content became invalid before the watcher noticed, the write
is refused and Juggler enters invalid-file mode without changing the file.

Changing an assignment retains its key spelling, spacing, line ending, and all
comments. When a comment is embedded inside a multiline value and the requested
edit cannot preserve it, Juggler refuses the edit and reports the affected path;
it never silently removes the comment. The user can edit that value directly in
the file.

An edit that selects a compiled default deletes the assignment but never
intentionally deletes adjacent comments. Empty tables and detached comments may
remain rather than risking removal of user-authored text.

### External edit

The watcher monitors the containing directory with a `DispatchSource` so it
observes editor-style atomic rename and replacement. Relevant events are
debounced by approximately 250 milliseconds. A content revision suppresses the
notification produced by Juggler's own write.

The controller reads and validates a complete candidate from one snapshot. On
success it applies settings and shortcuts together on the main actor, then runs
the reconciler. On failure it retains the last valid runtime snapshot, disables
editing, and exposes the diagnostic. Fixing the file automatically clears the
error and applies the new candidate.

### Missing file during file mode

Deletion or temporary disappearance is an invalid active-file state, not a
request to merge or fall back. Juggler retains the last valid snapshot for the
session and reports that the file is missing. Source selection runs again at
the next launch.

## Preservation, Validation, and Diagnostics

Generated files use canonical formatting. Thereafter:

- Untouched text, whitespace, comments, table order, and unknown content remain
  byte-for-byte unchanged.
- A modified value may be rewritten canonically only when every comment in the
  assignment can be retained.
- Removing an assignment retains surrounding comments.
- Unknown keys and tables are preserved and produce nonblocking warnings.
- Unknown content under a reserved Juggler or ShortcutKit path must still have
  the structural shape required by that namespace.
- A known invalid value rejects the complete candidate.
- TOML syntax errors reject the complete candidate.
- Shortcut conflicts remain normal ShortcutKit conflicts; they do not make the
  file corrupt.

Diagnostics use a common value with severity, message, file URL, key path,
line, column, offending value, and expected value where available. Syntax
parsers may report only the first syntax error; semantic validation should
collect multiple independent issues from a syntactically valid file.

ShortcutKit supplies structured shortcut and TOML diagnostics. Juggler supplies
regular-setting diagnostics and combines them for the startup alert and runtime
status UI.

## Settings UI

General Settings gains a **Configuration** section.

When using macOS preferences it shows the resolved path and **Export to Config
File**. When using a valid file it shows the path, automatic-reload status,
**Open Config File**, and **Reveal in Finder**. Warnings and errors remain
visible in this section and in the menu-bar popover until resolved.

There is no separate enable toggle and no initial “switch back” button. The file
itself is the opt-in marker. The UI explains that removing it and restarting
Juggler returns to macOS settings.

Sparkle's update preferences remain enabled and editable in every configuration
mode because they are not file-backed Juggler settings.

`NSWorkspace` opens the file with the default associated editor. If that fails,
Juggler reports the error and retains **Reveal in Finder** as a fallback.

The confirmed **Uninstall Juggler** workflow moves `config.toml` to the Trash as
part of clearing settings. A failure is included in the uninstall summary and
does not silently claim that settings were removed.

## Side-effect Failures

The configuration value represents desired state. If reconciliation with an
external system fails, such as registering Launch at Login or starting a
terminal bridge, Juggler keeps the desired value and reports an operational
warning. The configuration file remains valid and is not rewritten to match the
failed external state. Reconciliation is idempotent so a later reload or retry
can bring the system into line.

## Compatibility and Delivery

ShortcutKit support lands and is released before Juggler adopts it. The change
is additive: current `FileStore` initializers, JSON behavior, store protocol,
and override semantics remain compatible.

Juggler then centralizes every configuration consumer in one change. Leaving a
subset of `@AppStorage` or direct `UserDefaults` reads would reintroduce merging,
so file-backed keys cannot be migrated piecemeal. Existing state-only uses stay
in place.

Upgrading Juggler does not create or modify a config file. Existing users remain
on the macOS backend until they export or create the file themselves.

## Testing

ShortcutKit tests:

- Byte-for-byte preservation of comments, whitespace, unknown keys, table
  order, and unrelated values.
- Local replacement, insertion, and deletion of scalar and shortcut values.
- Shared-instance write serialization and atomic replacement.
- Existing `FileStore` URL and JSON compatibility.
- Structured syntax and shortcut diagnostics.

Juggler tests:

- Every startup source-selection case, with deliberately conflicting file and
  `UserDefaults` values proving that no merge occurs.
- Sparse export, color conversion, enum validation, and state exclusion.
- Successful and failed export transitions.
- All-or-nothing settings and shortcut staging.
- Debouncing, self-write suppression, editor-style atomic replacement, file
  deletion, and recovery after an invalid edit.
- Startup invalid-file mode uses compiled defaults, disables editors, and never
  reads macOS configuration values.
- Reconciler behavior and operational error reporting.
- Uninstall moves the active config file to the Trash or reports the failure.

A focused manual pass verifies the startup alert, default-editor launch, Finder
reveal, and a real editor's save behavior. App-launching tests require explicit
user approval under the repository testing policy.

## Acceptance Criteria

- A valid config file is the sole configuration source for both Juggler and
  ShortcutKit.
- A missing file preserves current behavior.
- Export is atomic and switches both stores only after success.
- UI and external edits preserve comments and unrelated content.
- Valid external edits reload automatically; invalid edits never partially
  apply.
- Invalid startup gives actionable details and still allows Juggler to run with
  compiled defaults.
- Every durable portable setting inside Juggler's configuration boundary has a
  typed model field and stable TOML path; operational and framework-owned state
  remains outside the file.
- No direct configuration read bypasses `JugglerSettings` or the active shortcut
  store.
