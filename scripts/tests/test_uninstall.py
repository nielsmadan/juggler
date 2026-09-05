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
