const { execFileSync } = require("node:child_process");
const { readFileSync } = require("node:fs");

const [specPath] = process.argv.slice(2);
const spec = JSON.parse(readFileSync(specPath, "utf8"));
const home = process.env.HOME;

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const absolute = (path) => (path.startsWith("/") ? path : `${home}/${path.replace(/^~\//, "")}`);

function ingest(step) {
  const bin = process.env.HLS_BIN ?? "/Applications/Juggler.app/Contents/MacOS/hooklinesinker";
  execFileSync(bin, ["ingest", "--agent", spec.agent, "--event", step.event], {
    input: JSON.stringify({ ...step.payload, cwd: absolute(step.payload.cwd) }),
    stdio: ["pipe", "ignore", "inherit"],
  });
}

async function post(step) {
  const body = {
    ...step.payload,
    terminal: { ...step.payload.terminal, cwd: absolute(step.payload.terminal.cwd), sessionId: process.env.ITERM_SESSION_ID ?? "", terminalType: "iterm2" },
  };
  const response = await fetch("http://127.0.0.1:7483/hook", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`hook server answered ${response.status}`);
}

async function send(step) {
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      if (spec.transport === "http") await post(step);
      else ingest(step);
      return;
    } catch (error) {
      console.error(`${step.event} attempt ${attempt} failed: ${error.message}`);
      await wait(2000);
    }
  }
}

async function main() {
  for (const step of spec.steps) {
    await send(step);
    await wait(step.delayMs ?? 400);
  }
  setInterval(() => {}, 1 << 30);
}

main();
