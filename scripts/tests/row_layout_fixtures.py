import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

GUEST_ROOT = "$HOME/row-layout-fixtures"
HERE = Path(__file__).resolve().parent
LONG_TITLE = ("Refactor the session row layout so that a very long agent supplied title is truncated "
              "cleanly across the whole row and never wraps onto a second line of text")[:120]
DEEP_CWD = "work/clients/acme-corporation/platform/services/session-gateway/packages/row-layout-long-folder-name"
LONG_MODEL = "claude-opus-4-7-20260101-extended-thinking-preview"
LONG_BRANCH = "feature/row-layout-long-branch-name-with-many-segments"


def claude(session_id, cwd, **native):
    return {"session_id": session_id, "cwd": cwd, **native}


def step(event, payload, delay_ms=400):
    return {"event": event, "payload": payload, "delayMs": delay_ms}


def sessions():
    long_cwd = claude("rl-claude-long", DEEP_CWD, model=LONG_MODEL, effort={"level": "high"},
                      permission_mode="acceptEdits", session_title=LONG_TITLE)
    children = [{"type": "subagent", "status": "running"}, {"type": "subagent", "status": "running"},
                {"type": "subagent", "status": "finished"}]
    perm = claude("rl-claude-permission", "work/permission", model="claude-sonnet-5",
                  effort={"level": "medium"}, permission_mode="default", session_title="Approve a shell command")
    codex = claude("rl-codex-short", "work/app", model="gpt-5.5-codex", permission_mode="default")
    qwen = claude("rl-qwen-problem", "work/qwen-service", model="qwen3-coder", permission_mode="yolo")
    kimi = claude("rl-kimi", "work/kimi-tool", model="kimi-k2", session_title="Refactor parser")
    droid = claude("rl-droid-sparse", "work/droid", permission_mode="auto-high")
    bare = claude("rl-claude-bare", "work/bare")
    return [
        {"name": "claude-long", "agent": "claude", "transport": "ingest", "cwd": DEEP_CWD,
         "branch": LONG_BRANCH, "tabTitle": "claude " + LONG_TITLE[:60], "windowTitle": "long values and turns",
         "steps": [
             step("SessionStart", long_cwd),
             step("UserPromptSubmit", long_cwd), step("Stop", long_cwd),
             step("UserPromptSubmit", long_cwd), step("Stop", long_cwd),
             step("UserPromptSubmit", long_cwd),
             step("PreToolUse", {**long_cwd, "tool_name": "Bash", "background_tasks": children}),
         ]},
        {"name": "claude-permission", "agent": "claude", "transport": "ingest", "cwd": "work/permission",
         "branch": "main", "tabTitle": "permission", "windowTitle": "permission state",
         "steps": [
             step("SessionStart", perm), step("UserPromptSubmit", perm),
             step("PermissionRequest", {**perm, "tool_name": "Bash"}),
         ]},
        {"name": "codex-short", "agent": "codex", "transport": "ingest", "cwd": "work/app",
         "branch": "dev", "tabTitle": "app", "windowTitle": "codex",
         "steps": [
             step("SessionStart", codex), step("UserPromptSubmit", codex),
             step("SubagentStart", {**codex, "agent_id": "rl-codex-child-1"}),
             step("PreToolUse", {**codex, "tool_name": "apply_patch"}),
         ]},
        {"name": "qwen-problem", "agent": "qwen", "transport": "ingest", "cwd": "work/qwen-service",
         "branch": "fix/rate-limit", "tabTitle": "qwen service", "windowTitle": "qwen",
         "steps": [
             step("SessionStart", qwen), step("UserPromptSubmit", qwen),
             step("Stop", {**qwen, "context_usage": 0.414}),
             step("UserPromptSubmit", qwen),
             step("StopFailure", {**qwen, "error": "RateLimitError"}),
         ]},
        {"name": "kimi-working", "agent": "kimi", "transport": "ingest", "cwd": "work/kimi-tool",
         "branch": "main", "tabTitle": "kimi", "windowTitle": "kimi",
         "steps": [
             step("SessionStart", kimi), step("TurnStarted", kimi),
             step("PreToolUse", {**kimi, "tool_name": "Shell"}),
         ]},
        {"name": "droid-sparse", "agent": "droid", "transport": "ingest", "cwd": "work/droid",
         "branch": "main", "tabTitle": "droid", "windowTitle": "droid",
         "steps": [step("SessionStart", droid), step("UserPromptSubmit", droid), step("Stop", droid)]},
        {"name": "claude-bare", "agent": "claude", "transport": "ingest", "cwd": "work/bare",
         "branch": "main", "tabTitle": "bare", "windowTitle": "missing values",
         "steps": [step("SessionStart", bare)]},
        {"name": "antigravity", "agent": "antigravity", "transport": "http", "cwd": "work/antigravity",
         "branch": "main", "tabTitle": "antigravity", "windowTitle": "antigravity",
         "steps": [
             step("PreInvocation", antigravity_payload("PreInvocation", "work/antigravity")),
             step("Stop", antigravity_payload("Stop", "work/antigravity", termination="error")),
         ]},
    ]


def antigravity_payload(event, cwd, termination=None):
    hook_input = {"session_id": "rl-antigravity", "model": "gemini-3-pro"}
    if termination:
        hook_input["termination_reason"] = termination
    return {"agent": "antigravity", "event": event, "hookInput": hook_input,
            "terminal": {"cwd": f"~/{cwd}"}, "git": {"branch": "main", "repo": "antigravity"}}


def describe(session):
    lines = [f"{session['name']}: agent={session['agent']} transport={session['transport']} "
             f"events={' > '.join(s['event'] for s in session['steps'])}"]
    lines += [f"  {s['event']} {json.dumps(s['payload'], sort_keys=True)}" for s in session["steps"]]
    return "\n".join(lines)


def spec_for(session):
    return {"agent": session["agent"], "transport": session["transport"], "steps": session["steps"]}


def tart(vm, *command, stdin=None):
    return subprocess.run(["tart", "exec", *(["-i"] if stdin is not None else []), vm, *command],
                          input=stdin, text=True, check=True, capture_output=True, timeout=90).stdout


def guest_sh(vm, script, stdin=None):
    return tart(vm, "/bin/sh", "-c", script, stdin=stdin)


def iterm(vm_skill, vm, *args):
    return subprocess.run([sys.executable, str(Path(vm_skill) / "scripts/iterm.py"), "--vm", vm, *args],
                          text=True, check=True, capture_output=True, timeout=90).stdout.strip()


def tab_command(session):
    cwd = f'"$HOME/{session["cwd"]}"'
    node = f'node "{GUEST_ROOT}/agents/{session["agent"]}" "{GUEST_ROOT}/specs/{session["name"]}.json"'
    branch = shlex.quote(session["branch"])
    git = (f"(git init -q 2>/dev/null; git checkout -q -B {branch} 2>/dev/null; "
           "git rev-parse -q --verify HEAD >/dev/null 2>&1 || "
           "git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; true)")
    return (f"mkdir -p {cwd} && cd {cwd} && {git} && "
            f"printf '\\033]1;%s\\007\\033]2;%s\\007' {shlex.quote(session['tabTitle'])} "
            f"{shlex.quote(session['windowTitle'])} && {node}")


def provision(vm):
    here = HERE / "fake_agent.cjs"
    guest_sh(vm, f'mkdir -p "{GUEST_ROOT}/agents" "{GUEST_ROOT}/specs" && '
                 f'cat > "{GUEST_ROOT}/fake_agent.cjs"', stdin=here.read_text())
    for session in sessions():
        guest_sh(vm, f'cat > "{GUEST_ROOT}/specs/{session["name"]}.json"', stdin=json.dumps(spec_for(session)))
    for agent in sorted({s["agent"] for s in sessions()}):
        guest_sh(vm, f'cp "{GUEST_ROOT}/fake_agent.cjs" "{GUEST_ROOT}/agents/{agent}"')


def selected(names):
    unknown = set(names) - {session["name"] for session in sessions()}
    if unknown:
        raise ValueError(f"unknown fixture sessions: {', '.join(sorted(unknown))}")
    return [session for session in sessions() if not names or session["name"] in names]


def stop_pattern(names):
    return "row-layout-fixtures/specs/(" + "|".join(names) + ")\\.json" if names else "row-layout-fixtures/agents/"


def stop_previous(vm, names):
    subprocess.run(["tart", "exec", vm, "/usr/bin/pkill", "-f", stop_pattern(names)], check=False)


def run(vm, vm_skill, hls_bin, names):
    chosen = selected(names)
    stop_previous(vm, names)
    provision(vm)
    env = f"export HLS_BIN={shlex.quote(hls_bin)}; " if hls_bin else ""
    for session in chosen:
        tab = iterm(vm_skill, vm, "new-tab")
        iterm(vm_skill, vm, "send", "--session", tab, "--text", env + tab_command(session), "--submit")
        print(f"{session['name']}: tab {tab}", flush=True)


def main(argv):
    parser = argparse.ArgumentParser(description="Create fake agent sessions for the row layout VM test")
    parser.add_argument("--dry-run", action="store_true", help="print agents, events and payloads only")
    parser.add_argument("--vm")
    parser.add_argument("--vm-skill", help="macos-vm skill directory")
    parser.add_argument("--hls-bin", default="")
    parser.add_argument("--only", nargs="+", default=[], metavar="NAME",
                        help="restart only these sessions, leaving the others running")
    args = parser.parse_args(argv)
    if args.dry_run:
        print("\n".join(describe(session) for session in sessions()))
        return 0
    if not args.vm or not args.vm_skill:
        parser.error("--vm and --vm-skill are required unless --dry-run")
    run(args.vm, args.vm_skill, args.hls_bin, args.only)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
