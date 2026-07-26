import {
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
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
  "bin/keykong",
  "libexec/KeyKongPrompt.app/Contents/Info.plist",
  "libexec/KeyKongPrompt.app/Contents/MacOS/keykong-prompt",
  "libexec/KeyKongPrompt.app/Contents/Resources/KeyKong.icns",
  "libexec/KeyKongPrompt.app/Contents/Resources/keykong-app-icon-emblem.png",
  "libexec/KeyKongPrompt.app/Contents/_CodeSignature/CodeResources",
];
if (layout.join("\n") !== expectedLayout.join("\n")) {
  throw new Error(`unexpected packaged layout: ${layout.join(", ")}`);
}

const cli = join(root, "dist/bin/keykong");
const app = join(root, "dist/libexec/KeyKongPrompt.app");
const helper = join(app, "Contents/MacOS/keykong-prompt");
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
  CFBundleExecutable: "keykong-prompt",
  CFBundleIconFile: "KeyKong.icns",
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

const icon = join(app, "Contents/Resources/KeyKong.icns");
const emblem = join(
  app,
  "Contents/Resources/keykong-app-icon-emblem.png",
);
if (
  readFileSync(emblem).compare(
    readFileSync(join(root, "assets/keykong-app-icon-emblem.png")),
  ) !== 0
) {
  throw new Error("packaged Prompt Adapter emblem does not match its source");
}
const iconCheckDirectory = mkdtempSync(join(tmpdir(), "keykong-icon-"));
try {
  const iconCheck = Bun.spawnSync(
    [
      "/usr/bin/iconutil",
      "-c",
      "iconset",
      "-o",
      join(iconCheckDirectory, "KeyKong.iconset"),
      icon,
    ],
    { stdout: "pipe", stderr: "pipe" },
  );
  if (iconCheck.exitCode !== 0) {
    throw new Error("packaged Prompt Adapter icon is invalid");
  }
} finally {
  rmSync(iconCheckDirectory, { recursive: true, force: true });
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
  version.stdout.toString() !== `keykong ${packageVersion}\n`
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
