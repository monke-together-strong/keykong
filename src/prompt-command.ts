import type { Execution } from "./command";
import type { Deadline } from "./deadline";
import { KeyKongError } from "./errors";
import {
  readWebPromptSettings,
  removeWebPromptSettings,
  writeWebPromptSettings,
} from "./web-prompt";

const mountPath = "/keykong";
const usage = "usage: keykong prompt [native|web [--allow <login>]]";

export async function promptCommand(
  args: string[],
  deadline: Deadline,
): Promise<Execution> {
  const settings = await readWebPromptSettings();
  if (args.length === 1) {
    return {
      result: settings
        ? { prompt: "web", url: settings.url }
        : { prompt: "native" },
      exitCode: 0,
    };
  }
  if (args.length === 2 && args[1] === "native") {
    if (settings) {
      await tailscale(
        ["serve", "--https=443", "--set-path", mountPath, "off"],
        deadline,
      );
      await removeWebPromptSettings();
    }
    return { result: { prompt: "native" }, exitCode: 0 };
  }
  if (
    args[1] === "web" &&
    (args.length === 2 || (args.length === 4 && args[2] === "--allow"))
  ) {
    const { host, owner } = await tailscaleNode(deadline);
    const allow = args[3] ?? owner;
    if (!allow) {
      throw new KeyKongError(
        "CLI_USAGE",
        "this Tailscale node is tagged; pass --allow <login>",
        2,
      );
    }
    const port = settings?.port ?? freePort();
    await tailscale(
      [
        "serve",
        "--bg",
        "--yes",
        "--https=443",
        "--set-path",
        mountPath,
        `http://127.0.0.1:${port}`,
      ],
      deadline,
    );
    const url = `https://${host}${mountPath}`;
    await writeWebPromptSettings({ url, port, allow });
    return { result: { prompt: "web", url }, exitCode: 0 };
  }
  throw new KeyKongError("CLI_USAGE", usage, 2);
}

async function tailscaleNode(
  deadline: Deadline,
): Promise<{ host: string; owner?: string }> {
  const output = await tailscale(["status", "--json"], deadline);
  let status: {
    Self?: { DNSName?: string; UserID?: number; Tags?: string[] };
    User?: Record<string, { LoginName?: string }>;
  };
  try {
    status = JSON.parse(output);
  } catch {
    status = {};
  }
  const host = status.Self?.DNSName?.replace(/\.$/, "");
  if (!host) {
    throw new KeyKongError(
      "PROMPT_FAILED",
      "tailscale did not report this node's name",
      1,
    );
  }
  const owner = status.Self?.Tags?.length
    ? undefined
    : status.User?.[String(status.Self?.UserID)]?.LoginName;
  return { host, owner };
}

function freePort(): number {
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch: () => new Response(),
  });
  const port = server.port!;
  server.stop(true);
  return port;
}

async function tailscale(args: string[], deadline: Deadline): Promise<string> {
  let subprocess: Bun.Subprocess<"ignore", "pipe", "pipe">;
  try {
    subprocess = Bun.spawn(["tailscale", ...args], {
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch {
    throw new KeyKongError("PROMPT_FAILED", "tailscale could not be started", 1);
  }
  const [output, error, exitCode] = await deadline.run(
    Promise.all([
      new Response(subprocess.stdout).text(),
      new Response(subprocess.stderr).text(),
      subprocess.exited,
    ]),
    () => subprocess.kill(9),
  );
  if (exitCode !== 0) {
    throw new KeyKongError(
      "PROMPT_FAILED",
      `tailscale ${args[0]} failed: ${error.trim()}`,
      1,
    );
  }
  return output;
}
