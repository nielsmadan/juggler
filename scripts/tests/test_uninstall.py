import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


RESOURCES = Path(__file__).resolve().parents[2] / "juggler/Resources"


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="juggler cleanup ")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.environment = dict(os.environ)
        for key in ("XDG_CONFIG_HOME", "KITTY_CONFIG_DIRECTORY", "OPENCODE_CONFIG_DIR", "PI_CODING_AGENT_DIR"):
            self.environment.pop(key, None)
        self.environment["XDG_DATA_HOME"] = str(self.directory / "data")
        self.environment["XDG_STATE_HOME"] = str(self.directory / "state")

    def write(self, relative, contents="installed"):
        path = self.directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def run_cleanup(self, script=None):
        return subprocess.run(
            ["/bin/bash", str(script or RESOURCES / "hooks/uninstall.sh"),
             "--home-directory", str(self.directory), "--skip-permissions"],
            env=self.environment, text=True, capture_output=True,
        )

    def shared_hooks(self, remaining="missing", uninstall_status=0, status_override=None,
                     after_override=None):
        hooks = self.directory / ".codex/hooks.json"
        active = self.directory / "data/hooklinesinker/bin/hooklinesinker"
        executable = self.directory / "data/hooklinesinker/versions/1.0.0/hooklinesinker"
        events = (("SessionStart", "session_start", 5), ("UserPromptSubmit", "user_prompt_submit", 5),
                  ("PreToolUse", "pre_tool_use", 5), ("PostToolUse", "post_tool_use", 5),
                  ("PreCompact", "pre_compact", 5), ("PostCompact", "post_compact", 5),
                  ("PermissionRequest", "permission_request", 5), ("Stop", "stop", 5),
                  ("SessionEnd", "session_end", 3))
        entries, blocks = [], []
        for event, snake, timeout in events:
            command = f"'{active}' ingest --agent codex --event {event}"
            entries.append({"event": event, "groupIndex": 0, "command": command})
            fingerprint = {"event_name": snake, "hooks": [
                {"async": False, "command": command, "timeout": timeout, "type": "command"},
            ]}
            digest = hashlib.sha256(json.dumps(fingerprint, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            blocks.append(f'[hooks.state."{hooks}:{snake}:0:0"]\ntrusted_hash = "sha256:{digest}"\n')
        registration = {"protocol": 1, "agent": "codex", "state": "installed",
                        "path": str(hooks), "entries": entries}
        after = dict(registration, state=remaining, entries=[] if remaining == "missing" else entries)
        if status_override is not None:
            registration = status_override
        if after_override is not None:
            after = after_override
        log = self.directory / "hls-argv.jsonl"
        marker = self.directory / "hls-uninstalled"
        script = f'''#!/usr/bin/python3
import json
import sys
from pathlib import Path
with open({str(log)!r}, "a") as file:
    file.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:2] == ["uninstall"]:
    if {uninstall_status}:
        print("uninstall failed", file=sys.stderr)
        sys.exit({uninstall_status})
    Path({str(marker)!r}).touch()
    if {remaining!r} == "missing":
        if Path({str(active)!r}).is_symlink():
            Path({str(active)!r}).unlink()
        Path({str(hooks)!r}).unlink()
    print("removed consumer juggler")
else:
    print({json.dumps(after)!r} if Path({str(marker)!r}).exists() else {json.dumps(registration)!r})
'''
        self.write(str(executable.relative_to(self.directory)), script).chmod(0o755)
        active.parent.mkdir(parents=True, exist_ok=True)
        active.symlink_to(executable)
        self.write(".codex/hooks.json", json.dumps({"hooks": {
            entry["event"]: [{"hooks": [{"type": "command", "command": entry["command"]}]}]
            for entry in entries
        }}))
        return "".join(blocks), log, active

    def test_last_consumer_removes_canonical_trust_after_shared_hooks(self):
        blocks, log, active = self.shared_hooks()
        retained = 'model = "keep-model"\n\n'
        config = self.write(".codex/config.toml", retained + blocks)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), retained)
        self.assertEqual([json.loads(line) for line in log.read_text().splitlines()], [
            ["hooks", "status", "--agent", "codex", "--json"],
            ["uninstall", "--consumer", "juggler"],
            ["hooks", "status", "--agent", "codex", "--json"],
        ])
        self.assertFalse(active.exists())
        repeated = self.run_cleanup()
        self.assertEqual(repeated.returncode, 0, repeated.stdout + repeated.stderr)
        self.assertEqual(config.read_text(), retained)

    def test_remaining_consumer_keeps_canonical_codex_trust(self):
        blocks, _, active = self.shared_hooks(remaining="installed")
        config = self.write(".codex/config.toml", blocks)
        hooks = self.directory / ".codex/hooks.json"
        original_hooks = hooks.read_text()
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), blocks)
        self.assertEqual(hooks.read_text(), original_hooks)
        self.assertTrue(active.is_symlink())
        self.assertIn("Kept Codex trust for the remaining shared hooks", result.stdout)

    def test_failed_shared_uninstall_preserves_canonical_trust(self):
        blocks, log, active = self.shared_hooks(uninstall_status=1)
        config = self.write(".codex/config.toml", blocks)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), blocks)
        self.assertTrue(active.is_symlink())
        self.assertEqual(len(log.read_text().splitlines()), 2)
        self.assertIn("uninstall failed", result.stderr)

    def test_unreadable_post_uninstall_status_preserves_canonical_trust(self):
        blocks, _, _ = self.shared_hooks(after_override={"protocol": 2})
        config = self.write(".codex/config.toml", blocks)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), blocks)
        self.assertIn("Unsupported hooklinesinker status protocol", result.stderr)

    def test_invalid_shared_status_does_not_uninstall(self):
        for status in ({"protocol": True}, {"protocol": 2}, {"protocol": 1}, []):
            with self.subTest(status=status):
                blocks, log, active = self.shared_hooks(status_override=status)
                config = self.write(".codex/config.toml", blocks)
                result = self.run_cleanup()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(config.read_text(), blocks)
                self.assertEqual([json.loads(line) for line in log.read_text().splitlines()], [
                    ["hooks", "status", "--agent", "codex", "--json"],
                ])
                active.unlink()
                log.unlink()

    def test_canonical_trust_cleanup_preserves_commented_tables_and_multiline_strings(self):
        blocks, _, _ = self.shared_hooks()
        prefix = f'instructions = """\n{blocks}"""\n\n'
        suffix = ('[mcp_servers.example] # user annotation\ncommand = "keep-server"\n'
                  'arguments = [\n["one", "two"], # nested array\n]\n'
                  '[[projects]] # personal projects\nname = "keep-project"\n')
        config = self.write(".codex/config.toml", prefix + blocks + suffix)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), prefix + suffix)

    def test_canonical_trust_cleanup_preserves_foreign_hash_and_file_metadata(self):
        blocks, _, _ = self.shared_hooks()
        header = blocks.splitlines()[0]
        retained = f'{header}\ntrusted_hash = "sha256:user"\n'
        target = self.write("dotfiles/config.toml", retained + "\n".join(blocks.splitlines()[2:]) + "\n")
        target.chmod(0o600)
        config = self.directory / ".codex/config.toml"
        config.symlink_to(target)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target.read_text(), retained)
        self.assertTrue(config.is_symlink())
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_moved_app_uses_its_embedded_helper_when_shared_binary_is_missing(self):
        blocks, log, active = self.shared_hooks()
        executable = active.resolve()
        active.unlink()
        contents = self.directory / "Caskroom/juggler/1.7.3/Juggler.app/Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        for source in (RESOURCES / "hooks/uninstall.sh", RESOURCES / "integration_cleanup.py",
                       RESOURCES / "codex_config_cleanup.py"):
            shutil.copy2(source, resources / source.name)
        helper = contents / "MacOS/hooklinesinker"
        helper.parent.mkdir()
        shutil.copy2(executable, helper)
        config = self.write(".codex/config.toml", blocks)
        result = self.run_cleanup(resources / "uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), "")
        self.assertEqual(len(log.read_text().splitlines()), 3)

    def test_removes_all_integrations_preserving_shared_settings_and_is_idempotent(self):
        user_hook = {"type": "command", "command": "user-hook"}
        mentions_juggler = {"type": "command", "command": "echo juggler/notify.sh"}
        for agent, filename in (("claude", "settings.json"), ("codex", "hooks.json")):
            notify = self.write(f".{agent}/hooks/juggler/notify.sh")
            command = f"'{notify}' Stop" if agent == "codex" else "~/.claude/hooks/juggler/notify.sh Stop"
            self.write(f".{agent}/{filename}", json.dumps({
                "theme": "dark",
                "hooks": {"Stop": [{"matcher": "*", "hooks": [
                    user_hook, {"type": "command", "command": command}, mentions_juggler,
                ]}]},
            }))
            self.write(f".{agent}/{filename}.juggler-backup")
        self.write(".gemini/hooks/juggler/notify.sh")
        self.write(".gemini/config/hooks.json", json.dumps({"juggler": {}, "user": {"Stop": []}}))
        self.write(".config/kitty/juggler_watcher.py")
        kitty_settings = "allow_remote_control yes\nlisten_on unix:/tmp/kitty\nwatcher user.py\n"
        self.write(".config/kitty/kitty.conf", kitty_settings + "watcher ~/.config/kitty/juggler_watcher.py\n")
        self.write(".config/opencode/plugins/juggler-opencode.ts")
        self.write(".pi/agent/extensions/juggler-pi.ts")
        tmux = self.write(".tmux.conf", 'set -g update-environment "ITERM_SESSION_ID"\n')
        for _ in range(2):
            result = self.run_cleanup()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for agent, filename in (("claude", "settings.json"), ("codex", "hooks.json")):
            data = json.loads((self.directory / f".{agent}/{filename}").read_text())
            self.assertEqual(data, {"theme": "dark", "hooks": {"Stop": [
                {"matcher": "*", "hooks": [user_hook, mentions_juggler]},
            ]}})
            self.assertFalse((self.directory / f".{agent}/hooks/juggler").exists())
        self.assertEqual(json.loads((self.directory / ".gemini/config/hooks.json").read_text()), {"user": {"Stop": []}})
        self.assertEqual((self.directory / ".config/kitty/kitty.conf").read_text(), kitty_settings)
        self.assertEqual(tmux.read_text(), 'set -g update-environment "ITERM_SESSION_ID"\n')
        for path in (".gemini/hooks/juggler", ".config/kitty/juggler_watcher.py",
                     ".config/opencode/plugins/juggler-opencode.ts", ".pi/agent/extensions/juggler-pi.ts"):
            self.assertFalse((self.directory / path).exists(), path)

    def test_codex_preserves_later_settings_and_unrelated_trust(self):
        hooks = self.directory / ".codex/hooks.json"
        notify = self.write(".codex/hooks/juggler/notify.sh")
        self.write(".codex/hooks.json", json.dumps({"hooks": {"Stop": [
            {"hooks": [{"command": f"echo '{notify}'"}]},
            {"hooks": [{"command": f"'{notify}' Stop"}]},
        ]}}))
        retained = ('[features]\nhooks = true\n\nmodel = "new-model"\n\n'
                    f'[hooks.state."{hooks}:stop:0:0"]\ntrusted_hash = "sha256:user"\n\n')
        config = self.write(".codex/config.toml", retained +
                            f'[hooks.state."{hooks}:stop:1:0"]\ntrusted_hash = "sha256:juggler"\n')
        self.write(".codex/config.toml.juggler-backup", 'model = "old-model"\n')
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), retained)
        self.assertFalse((self.directory / ".codex/config.toml.juggler-backup").exists())

    def test_codex_preserves_commented_tables_and_multiline_strings(self):
        hooks = self.directory / ".codex/hooks.json"
        header = f'[hooks.state."{hooks}:stop:0:0"]'
        for quote in ('"""', "'''", '""""', "'''''"):
            for comment in ("", " # Juggler trust"):
                with self.subTest(quote=quote, comment=comment):
                    notify = self.write(".codex/hooks/juggler/notify.sh")
                    self.write(".codex/hooks.json", json.dumps({"hooks": {"Stop": [
                        {"hooks": [{"command": f"'{notify}' Stop"}]},
                    ]}}))
                    prefix = ('title = "keep\u2028me"\n'
                              f'instructions = {quote}\n{header}\n'
                              f'trusted_hash = "sha256:example"\n{quote}\n\n')
                    suffix = ('[profiles."review# ]"] # personal settings\nmodel = "keep-me"\n'
                              'arguments = [\n["one", "two"], # nested array\n]\n'
                              '[[projects]] # personal projects\nname = "keep-this-too"\n')
                    config = self.write(".codex/config.toml", prefix + header + comment +
                                        '\ntrusted_hash = "sha256:juggler"\n' + suffix)
                    self.write(".codex/config.toml.juggler-backup", "recovery")
                    result = self.run_cleanup()
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(config.read_text(), prefix + suffix)

    def test_codex_preserves_files_when_toml_has_unterminated_values(self):
        hooks = self.directory / ".codex/hooks.json"
        for value in ('"""unfinished', '"unfinished', "[1, 2", '{name = "unfinished"'):
            with self.subTest(value=value):
                notify = self.write(".codex/hooks/juggler/notify.sh")
                registration = json.dumps({"hooks": {"Stop": [
                    {"hooks": [{"command": f"'{notify}' Stop"}]},
                ]}})
                hooks.write_text(registration)
                original = (f'[hooks.state."{hooks}:stop:0:0"]\ntrusted_hash = "sha256:juggler"\n'
                            f'[profiles.review]\nsetting = {value}\n')
                config = self.write(".codex/config.toml", original)
                backup = self.write(".codex/config.toml.juggler-backup", "recovery")
                result = self.run_cleanup()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Cleanup failed: Codex:", result.stderr)
                self.assertEqual(config.read_text(), original)
                self.assertEqual(hooks.read_text(), registration)
                self.assertEqual(notify.read_text(), "installed")
                self.assertEqual(backup.read_text(), "recovery")

    def test_preserves_symlinks_and_file_permissions(self):
        notify = self.write(".claude/hooks/juggler/notify.sh")
        target = self.write("dotfiles/settings.json", json.dumps({"theme": "dark", "hooks": {"Stop": [
            {"hooks": [{"command": f"'{notify}' Stop"}]},
        ]}}))
        target.chmod(0o600)
        settings = self.directory / ".claude/settings.json"
        settings.symlink_to(target)
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(settings.is_symlink())
        self.assertEqual(json.loads(target.read_text()), {"theme": "dark"})
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_malformed_agent_config_reports_failure_and_preserves_its_files(self):
        for contents in ("{broken", "[]", '{"hooks":{"Stop":{}}}'):
            with self.subTest(contents=contents):
                settings = self.write(".claude/settings.json", contents)
                notify = self.write(".claude/hooks/juggler/notify.sh")
                backup = self.write(".claude/settings.json.juggler-backup", "recovery")
                plugin = self.write(".config/opencode/plugins/juggler-opencode.ts")
                result = self.run_cleanup()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("Cleanup failed: Claude Code:", result.stderr)
                self.assertEqual(settings.read_text(), contents)
                self.assertEqual(notify.read_text(), "installed")
                self.assertEqual(backup.read_text(), "recovery")
                self.assertFalse(plugin.exists())

    def test_honors_custom_config_directories_and_tilde_paths(self):
        self.environment.update({"XDG_CONFIG_HOME": str(self.directory / "xdg"),
                                 "KITTY_CONFIG_DIRECTORY": "~/custom kitty",
                                 "OPENCODE_CONFIG_DIR": "~/custom opencode",
                                 "PI_CODING_AGENT_DIR": "~/custom pi"})
        paths = ["custom kitty/juggler_watcher.py", "custom opencode/plugins/juggler-opencode.ts",
                 "custom pi/extensions/juggler-pi.ts"]
        for path in paths:
            self.write(path)
        kitty = self.write("custom kitty/kitty.conf", "font_size 14\nwatcher juggler_watcher.py\n")
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(kitty.read_text(), "font_size 14\n")
        for path in paths:
            self.assertFalse((self.directory / path).exists(), path)

    def test_honors_xdg_config_home(self):
        self.environment["XDG_CONFIG_HOME"] = "~/xdg"
        watcher = self.write("xdg/kitty/juggler_watcher.py")
        plugin = self.write("xdg/opencode/plugins/juggler-opencode.ts")
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(watcher.exists())
        self.assertFalse(plugin.exists())

    def test_kitty_installer_cleanup_round_trip_with_spaces(self):
        kitty = self.directory / "custom kitty #config"
        self.environment["KITTY_CONFIG_DIRECTORY"] = str(kitty)
        retained = "font_size 14\nwatcher user.py\n"
        config = self.write("custom kitty #config/kitty.conf", retained)
        installed = subprocess.run(["/bin/bash", str(RESOURCES / "install_kitty_watcher.sh")],
                                   env=self.environment, capture_output=True, text=True)
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
        watcher = kitty / "juggler_watcher.py"
        self.assertEqual(watcher.read_bytes(), (RESOURCES / "juggler_watcher.py").read_bytes())
        result = self.run_cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(config.read_text(), retained + "\n")
        self.assertFalse(watcher.exists())

    @unittest.skipUnless(sys.platform == "darwin", "Code signing requires macOS")
    def test_cleanup_preserves_the_app_signature(self):
        app = self.directory / "Juggler.app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        for source in (RESOURCES / "hooks/uninstall.sh", RESOURCES / "integration_cleanup.py",
                       RESOURCES / "codex_config_cleanup.py"):
            shutil.copyfile(source, resources / source.name)
        executable = self.write("Juggler.app/Contents/MacOS/fixture")
        shutil.copyfile("/usr/bin/true", executable)
        executable.chmod(0o755)
        with (app / "Contents/Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL",
                          "CFBundleIdentifier": "com.nielsmadan.Juggler.cleanup-fixture"}, file)
        signed = subprocess.run(["codesign", "--force", "--sign", "-", str(app)],
                                capture_output=True, text=True)
        self.assertEqual(signed.returncode, 0, signed.stdout + signed.stderr)
        verification = ["codesign", "--verify", "--deep", "--strict", str(app)]
        before = subprocess.run(verification, capture_output=True, text=True)
        self.assertEqual(before.returncode, 0, before.stdout + before.stderr)
        self.environment.pop("PYTHONDONTWRITEBYTECODE", None)
        self.environment.pop("PYTHONPYCACHEPREFIX", None)
        result = self.run_cleanup(resources / "uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = subprocess.run(verification, capture_output=True, text=True)
        self.assertEqual(after.returncode, 0, after.stdout + after.stderr)

    def test_flattened_app_resources_run_after_app_is_moved_to_staging(self):
        staged = self.directory / "Caskroom/juggler/1.7.3/Juggler.app/Contents/Resources"
        staged.mkdir(parents=True)
        for source in (RESOURCES / "hooks/uninstall.sh", RESOURCES / "integration_cleanup.py",
                       RESOURCES / "codex_config_cleanup.py"):
            shutil.copy2(source, staged / source.name)
        extension = self.write(".pi/agent/extensions/juggler-pi.ts")
        result = self.run_cleanup(staged / "uninstall.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(extension.exists())


if __name__ == "__main__":
    unittest.main()
