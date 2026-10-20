import { z } from "zod";
import type { Execution } from "./command";
import type { Deadline } from "./deadline";
import { KeyKongError } from "./errors";
import {
  mountPath,
  readWebPromptSettings,
  removeWebPromptSettings,
  writeWebPromptSettings,
} from "./web-prompt";

const usage = "usage: keykong prompt [native|web [--allow <login>]]";

const nodeStatusSchema = z.object({
  Self: z.object({
    DNSName: z.string().min(1),
    UserID: z.number(),
    Tags: z.array(z.string()).optional(),
  }),
  User: z.record(z.string(), z.object({ LoginName: z.string() })).nullish(),
});

const serveStatusSchema = z.object({
  Web: z
    .record(z.string(), z.object({ Handlers: z.record(z.string(), z.unknown()) }))
    .optional(),
});

export async function promptCommand(
  args: string[],
  deadline: Deadline,
): Promise<Execution> {
  if (args.length === 1) {
    const settings = await deadline.run(readWebPromptSettings());
    return {
      result: settings
        ? { prompt: "web", url: settings.url }
        : { prompt: "native" },
      exitCode: 0,
    };
  }
  if (args.length === 2 && args[1] === "native") {
    // Check Tailscale itself so an interrupted switch can be finished.
    if (await mounted(deadline)) {
      await tailscale(
        ["serve", "--https=443", "--set-path", mountPath, "off"],
        deadline,
      );
    }
    await deadline.run(removeWebPromptSettings());
    return { result: { prompt: "native" }, exitCode: 0 };
  }
  if (
    args[1] === "web" &&
    (args.length === 2 ||
      (args.length === 4 && args[2] === "--allow" && args[3]!.trim()))
  ) {
    const { host, owner } = await tailscaleNode(deadline);
    const allow = args[3]?.trim() ?? owner;
    if (!allow) {
      throw new KeyKongError(
        "CLI_USAGE",
        "this Tailscale node is tagged; pass --allow <login>",
        2,
      );
    }
    const previous = await deadline.run(
      readWebPromptSettings().catch(() => undefined),
    );
    const port = previous?.port ?? freePort();
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
    await deadline.run(writeWebPromptSettings({ url, port, allow }));
    return { result: { prompt: "web", url }, exitCode: 0 };
  }
  throw new KeyKongError("CLI_USAGE", usage, 2);
}

async function tailscaleNode(deadline: Deadline) {
  const { Self, User } = await tailscaleJSON(
    ["status", "--json"],
    nodeStatusSchema,
    deadline,
  );
  return {
    host: Self.DNSName.replace(/\.$/, ""),
    owner: Self.Tags?.length ? undefined : User?.[Self.UserID]?.LoginName,
  };
}

async function mounted(deadline: Deadline) {
  const { host } = await tailscaleNode(deadline);
  const { Web } = await tailscaleJSON(
    ["serve", "status", "--json"],
    serveStatusSchema,
    deadline,
  );
  return mountPath in (Web?.[`${host}:443`]?.Handlers ?? {});
}

async function tailscaleJSON<Schema extends z.ZodType>(
  args: string[],
  schema: Schema,
  deadline: Deadline,
): Promise<z.infer<Schema>> {
  const output = await tailscale(args, deadline);
  let parsed: z.ZodSafeParseResult<z.infer<Schema>> | undefined;
  try {
    parsed = schema.safeParse(JSON.parse(output));
  } catch {}
  if (!parsed?.success) {
    throw new KeyKongError(
      "PROMPT_FAILED",
      `tailscale ${args.join(" ")} returned unexpected output`,
      1,
    );
  }
  return parsed.data;
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
