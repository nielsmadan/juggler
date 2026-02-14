// Juggler plugin for OpenCode
// Installed to ~/.config/opencode/plugins/juggler-opencode.ts
// Posts session events to Juggler's HTTP server for session tracking

const JUGGLER_PORT = process.env.JUGGLER_PORT || "7483";
const JUGGLER_URL = `http://localhost:${JUGGLER_PORT}/hook`;

// Detect terminal type from environment
function getTerminalInfo(): Record<string, string> {
  const env = process.env;
  const info: Record<string, string> = {
    cwd: process.cwd(),
  };

  if (env.KITTY_WINDOW_ID) {
    info.terminalType = "kitty";
    info.sessionId = env.KITTY_WINDOW_ID;
    if (env.KITTY_LISTEN_ON) info.kittyListenOn = env.KITTY_LISTEN_ON;
    if (env.KITTY_PID) info.kittyPid = env.KITTY_PID;
  } else if (env.ITERM_SESSION_ID) {
    info.terminalType = "iterm2";
    info.sessionId = env.ITERM_SESSION_ID;
  }

  return info;
}

// Get git info from working directory
async function getGitInfo(
  $: any
): Promise<{ branch: string; repo: string } | null> {
  try {
    const branch = (await $`git rev-parse --abbrev-ref HEAD 2>/dev/null`)
      .text()
      .trim();
    const toplevel = (await $`git rev-parse --show-toplevel 2>/dev/null`)
      .text()
      .trim();
    const repo = toplevel.split("/").pop() || "";
    return { branch, repo };
  } catch {
    return null;
  }
}

// Get tmux info if running inside tmux
function getTmuxInfo(): Record<string, string> | null {
  const pane = process.env.TMUX_PANE;
  if (!pane) return null;
  return { pane };
}

// Events we care about for session tracking
const TRACKED_EVENTS = new Set([
  "session.created",
  "session.status",
  "session.deleted",
  "session.compacted",
  "permission.asked",
  "server.instance.disposed",
]);

export const JugglerPlugin = async ({
  $,
}: {
  project: any;
  client: any;
  $: any;
  directory: string;
  worktree: string;
}) => {
  const terminal = getTerminalInfo();
  const git = await getGitInfo($);
  const tmux = getTmuxInfo();

  // Post session.created on plugin load so Juggler sees the session immediately,
  // even when OpenCode resumes a previous session (which skips session.created)
  await postEvent("session.created");

  async function postEvent(eventType: string, sessionId?: string) {
    const payload: Record<string, any> = {
      agent: "opencode",
      event: eventType,
      terminal,
    };

    if (sessionId) {
      payload.hookInput = { session_id: sessionId };
    }

    if (git) {
      payload.git = git;
    }

    if (tmux) {
      payload.tmux = tmux;
    }

    try {
      await fetch(JUGGLER_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(2000),
      });
    } catch {
      // Juggler not running — silently ignore
    }
  }

  return {
    event: async ({
      event,
    }: {
      event: { type: string; [key: string]: any };
    }) => {
      if (!TRACKED_EVENTS.has(event.type)) return;

      const sessionId =
        (event as any).properties?.sessionID ||
        (event as any).properties?.info?.id ||
        (event as any).session_id ||
        (event as any).sessionID;

      // Translate session.status into synthetic event with status type
      let eventName = event.type;
      if (event.type === "session.status") {
        const status = (event as any).properties?.status?.type;
        if (!status) return;
        eventName = `session.status.${status}`;
      }

      await postEvent(eventName, sessionId);
    },
  };
};
