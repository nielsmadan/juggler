import importlib.util
import io
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("row_layout_fixtures", Path(__file__).with_name("row_layout_fixtures.py"))
fixtures = importlib.util.module_from_spec(SPEC)
sys.dont_write_bytecode = True
SPEC.loader.exec_module(fixtures)


class RowLayoutFixturesTests(unittest.TestCase):
    def test_every_required_agent_has_a_session(self):
        agents = {session["agent"] for session in fixtures.sessions()}
        self.assertEqual(agents, {"claude", "codex", "qwen", "kimi", "droid", "antigravity"})

    def test_agent_title_is_capped_at_the_sanitizer_limit(self):
        self.assertEqual(len(fixtures.LONG_TITLE), 120)

    def test_session_ids_are_unique(self):
        ids = [step["payload"].get("session_id") or step["payload"]["hookInput"]["session_id"]
               for session in fixtures.sessions() for step in session["steps"][:1]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_dry_run_prints_every_session_without_spawning(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(fixtures.main(["--dry-run"]), 0)
        for session in fixtures.sessions():
            self.assertIn(f"{session['name']}: agent={session['agent']}", output.getvalue())

    def test_antigravity_posts_the_script_payload_shape(self):
        payload = fixtures.antigravity_payload("Stop", "work/x", termination="completed")
        self.assertEqual(payload["hookInput"]["termination_reason"], "completed")
        self.assertEqual(payload["agent"], "antigravity")

    def test_antigravity_ends_on_a_stop_with_a_visible_problem(self):
        session = next(s for s in fixtures.sessions() if s["agent"] == "antigravity")
        last = session["steps"][-1]
        self.assertEqual(last["event"], "Stop")
        self.assertNotIn(last["payload"]["hookInput"]["termination_reason"], ("model_stop", "completed"))

    def test_tab_command_seeds_a_commit_and_exports_the_helper_path(self):
        command = fixtures.tab_command(fixtures.sessions()[0])
        self.assertIn("commit -q --allow-empty", command)
        self.assertIn("git checkout -q -B", command)
        self.assertTrue(f"export HLS_BIN=/x; {command}".startswith("export HLS_BIN=/x; mkdir"))

    def test_events_are_valid_for_each_agent(self):
        allowed = {
            "claude": {"SessionStart", "UserPromptSubmit", "Stop", "PreToolUse", "PermissionRequest"},
            "codex": {"SessionStart", "UserPromptSubmit", "SubagentStart", "PreToolUse", "Stop"},
            "qwen": {"SessionStart", "UserPromptSubmit", "Stop", "StopFailure"},
            "kimi": {"SessionStart", "TurnStarted", "PreToolUse"},
            "droid": {"SessionStart", "UserPromptSubmit", "Stop"},
            "antigravity": {"PreInvocation", "Stop"},
        }
        for session in fixtures.sessions():
            events = {step["event"] for step in session["steps"]}
            self.assertLessEqual(events, allowed[session["agent"]], session["name"])

    def test_cwds_are_relative(self):
        self.assertTrue(all(not s["cwd"].startswith("/") for s in fixtures.sessions()))

    def test_only_selects_the_named_sessions(self):
        self.assertEqual([s["name"] for s in fixtures.selected(["antigravity"])], ["antigravity"])
        self.assertEqual(len(fixtures.selected([])), len(fixtures.sessions()))

    def test_only_rejects_an_unknown_session(self):
        with self.assertRaises(ValueError):
            fixtures.selected(["no-such-row"])

    def test_only_stops_just_the_named_agents(self):
        self.assertEqual(fixtures.stop_pattern(["antigravity", "qwen-problem"]),
                         "row-layout-fixtures/specs/(antigravity|qwen-problem)\\.json")
        self.assertEqual(fixtures.stop_pattern([]), "row-layout-fixtures/agents/")


if __name__ == "__main__":
    unittest.main()
