import { readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const helper = join(
  root,
  "dist/libexec/KeyKongPrompt.app/Contents/MacOS/keykong-prompt",
);
const diagnosticReportsDirectory = join(
  homedir(),
  "Library/Logs/DiagnosticReports",
);

function helperCrashReports(): Set<string> {
  try {
    return new Set(
      readdirSync(diagnosticReportsDirectory)
        .filter((name) => name.startsWith("keykong-prompt-")),
    );
  } catch {
    return new Set();
  }
}

function helperProcessIDs(): string[] {
  const result = Bun.spawnSync(
    ["/usr/bin/pgrep", "-x", "keykong-prompt"],
    { stdout: "pipe", stderr: "pipe" },
  );
  return result.exitCode === 0
    ? result.stdout.toString().trim().split("\n").filter(Boolean)
    : [];
}

const processesBefore = helperProcessIDs();
if (processesBefore.length > 0) {
  throw new Error(
    `cannot run UI smoke while Prompt Adapter is active: ${processesBefore.join(", ")}`,
  );
}

const reportsBefore = helperCrashReports();
const uiSmoke = Bun.spawnSync(
  [
    "/usr/bin/xcrun",
    "swift",
    join(root, "scripts/smoke-macos-ui.swift"),
    helper,
  ],
  { stdout: "inherit", stderr: "inherit" },
);

const crashReportDeadline = Date.now() + 5_000;
let newReports: string[] = [];
do {
  await Bun.sleep(250);
  newReports = [...helperCrashReports()]
    .filter((name) => !reportsBefore.has(name));
} while (newReports.length === 0 && Date.now() < crashReportDeadline);

const remainingProcesses = helperProcessIDs();
const failures = [
  ...(uiSmoke.exitCode === 0
    ? []
    : ["packaged Prompt Adapter UI smoke test failed"]),
  ...(newReports.length === 0
    ? []
    : [`packaged Prompt Adapter crashed: ${newReports.join(", ")}`]),
  ...(remainingProcesses.length === 0
    ? []
    : [`packaged Prompt Adapter remained active: ${remainingProcesses.join(", ")}`]),
];
if (failures.length > 0) {
  throw new Error(failures.join("; "));
}
