import { chmod, mkdtemp, open, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = join(root, "dist/bin/keykong");
const cliArguments = process.argv.slice(2);
const unknownArguments = cliArguments.filter((argument) => argument !== "-b");
if (unknownArguments.length > 0) {
  throw new Error(`Unknown argument: ${unknownArguments[0]}`);
}
if (cliArguments.includes("-b")) {
  const build = Bun.spawn([process.execPath, "run", "package:macos"], {
    cwd: root,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await build.exited;
  if (exitCode !== 0) {
    throw new Error(`Key Kong package build exited with status ${exitCode}`);
  }
}

const directory = await mkdtemp(join(tmpdir(), "keykong-ui-test-"));
const target = join(directory, "preview.env");
await chmod(directory, 0o700);
const targetFile = await open(target, "wx", 0o600);
try {
  await targetFile.chmod(0o600);
} finally {
  await targetFile.close();
}

const request = {
  id: "ui_test",
  title: "Credentials needed",
  fields: [
    { id: "github_token", label: "GitHub token", type: "secret" },
    { id: "deploy_token", label: "Deploy token", type: "secret" },
  ],
  deliveries: [
    {
      id: "github_token_env",
      path: target,
      operation: "set_env",
      key: "GITHUB_TOKEN",
      field: "github_token",
    },
    {
      id: "deploy_token_env",
      path: target,
      operation: "set_env",
      key: "DEPLOY_TOKEN",
      field: "deploy_token",
    },
  ],
};

try {
  const keykong = Bun.spawn([executable, "request", "-"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "inherit",
  });
  const output = new Response(keykong.stdout).text();
  keykong.stdin.write(JSON.stringify(request));
  keykong.stdin.end();

  const exitCode = await keykong.exited;
  const result = await output;
  await Bun.write(Bun.stdout, result);
  const wasCancelled = JSON.parse(result).status === "cancelled";
  if (exitCode !== 0 && !wasCancelled) {
    throw new Error(`Key Kong exited with status ${exitCode}`);
  }
} finally {
  await rm(directory, { recursive: true, force: true });
}
