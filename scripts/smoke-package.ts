import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const packageVersion = JSON.parse(
  readFileSync(join(root, "package.json"), "utf8"),
).version;
const dist = join(root, "dist");
const layout = readdirSync(dist, {
  recursive: true,
  withFileTypes: true,
})
  .filter((entry) => entry.isFile())
  .map((entry) => join(entry.parentPath, entry.name)
    .slice(dist.length + 1))
  .sort();
const expectedLayout = [
  "bin/key-kong",
  "libexec/KeyKongPrompt.app/Contents/Info.plist",
  "libexec/KeyKongPrompt.app/Contents/MacOS/key-kong-prompt",
  "libexec/KeyKongPrompt.app/Contents/_CodeSignature/CodeResources",
];
if (layout.join("\n") !== expectedLayout.join("\n")) {
  throw new Error(`unexpected packaged layout: ${layout.join(", ")}`);
}

const cli = join(root, "dist/bin/key-kong");
const app = join(root, "dist/libexec/KeyKongPrompt.app");
const helper = join(app, "Contents/MacOS/key-kong-prompt");
const infoPlist = join(app, "Contents/Info.plist");
const plistResult = Bun.spawnSync(
  ["/usr/bin/plutil", "-convert", "json", "-o", "-", infoPlist],
  { stdout: "pipe", stderr: "pipe" },
);
if (plistResult.exitCode !== 0) {
  throw new Error("packaged Prompt Adapter Info.plist is invalid");
}
const plist = JSON.parse(plistResult.stdout.toString());
const expectedPlist = {
  CFBundleDisplayName: "KeyKong",
  CFBundleExecutable: "key-kong-prompt",
  CFBundleIdentifier: "dev.keykong.prompt",
  CFBundleInfoDictionaryVersion: "6.0",
  CFBundleName: "KeyKong",
  CFBundlePackageType: "APPL",
  CFBundleShortVersionString: packageVersion,
  CFBundleVersion: packageVersion,
  LSMinimumSystemVersion: "13.0",
  NSPrincipalClass: "NSApplication",
};
for (const [key, value] of Object.entries(expectedPlist)) {
  if (plist[key] !== value) {
    throw new Error(`unexpected ${key} in Prompt Adapter Info.plist`);
  }
}
if ("LSUIElement" in plist || "LSBackgroundOnly" in plist) {
  throw new Error("Prompt Adapter must use regular activation policy");
}

for (const [target, deep] of [
  [cli, false],
  [helper, false],
  [app, true],
] as const) {
  const verification = Bun.spawnSync(
    ["/usr/bin/codesign", "--verify", "--strict", ...(deep ? ["--deep"] : []), target],
    { stdout: "pipe", stderr: "pipe" },
  );
  if (verification.exitCode !== 0) {
    throw new Error(`invalid signature: ${target}`);
  }
}

const version = Bun.spawnSync([cli, "--version"], {
  stdout: "pipe",
  stderr: "pipe",
});
if (
  version.exitCode !== 0 ||
  version.stdout.toString() !== `key-kong ${packageVersion}\n`
) {
  throw new Error("packaged CLI version smoke test failed");
}

const schema = Bun.spawnSync([cli, "schema"], {
  stdout: "pipe",
  stderr: "pipe",
});
if (schema.exitCode !== 0 || JSON.parse(schema.stdout.toString()).properties
  ?.schemaVersion?.const !== 1) {
  throw new Error("packaged CLI schema smoke test failed");
}

const invalidHelper = Bun.spawnSync(
  [helper],
  { stdin: new TextEncoder().encode("{}"), stdout: "pipe", stderr: "pipe" },
);
if (
  invalidHelper.exitCode !== 1 ||
  invalidHelper.stdout.toString() !== "" ||
  invalidHelper.stderr.toString() !== "native prompt failed\n"
) {
  throw new Error("packaged Prompt Adapter smoke test failed");
}

const diagnosticReportsDirectory = join(
  homedir(),
  "Library/Logs/DiagnosticReports",
);
function helperCrashReports(): Set<string> {
  try {
    return new Set(
      readdirSync(diagnosticReportsDirectory)
        .filter((name) => name.startsWith("key-kong-prompt-")),
    );
  } catch {
    return new Set();
  }
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
if (uiSmoke.exitCode !== 0) {
  throw new Error("packaged Prompt Adapter UI smoke test failed");
}
const crashReportDeadline = Date.now() + 5_000;
let newReports: string[] = [];
do {
  await Bun.sleep(250);
  newReports = [...helperCrashReports()]
    .filter((name) => !reportsBefore.has(name));
} while (newReports.length === 0 && Date.now() < crashReportDeadline);
if (newReports.length > 0) {
  throw new Error(
    `packaged Prompt Adapter crashed: ${newReports.join(", ")}`,
  );
}
const remainingHelper = Bun.spawnSync(
  ["/usr/bin/pgrep", "-x", "key-kong-prompt"],
  { stdout: "pipe", stderr: "pipe" },
);
if (remainingHelper.exitCode === 0) {
  throw new Error("packaged Prompt Adapter remained after UI smoke test");
}
