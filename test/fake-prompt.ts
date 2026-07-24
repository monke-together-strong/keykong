#!/usr/bin/env bun

export {};

const mode = process.env.KEY_KONG_FAKE_MODE ?? "submit";
const request = JSON.parse(await Bun.stdin.text()) as {
  deliveries: Array<{ path: string; operation: string; line?: number }>;
};

if (
  request.deliveries.some(
    (delivery) =>
      "template" in delivery ||
      "id" in delivery ||
      !("path" in delivery) ||
      !("operation" in delivery),
  )
) {
  process.exit(9);
}

if (mode === "cancel") {
  console.log('{"status":"cancelled"}');
} else if (mode === "response_only") {
  console.log(
    '{"status":"submitted","values":{"environment":"prod"}}',
  );
} else if (mode === "empty") {
  // Deliberately return EOF without a response.
} else if (mode === "malformed") {
  console.log("not-json");
} else if (mode === "invalid_submission") {
  console.log('{"status":"submitted","values":[]}');
} else if (mode === "extra") {
  console.log('{"status":"cancelled"} trailing');
} else if (mode === "nonzero") {
  process.exit(7);
} else if (mode === "crash") {
  process.kill(process.pid, "SIGKILL");
  await Bun.sleep(5_000);
} else if (mode === "replace_last") {
  const target = request.deliveries.at(-1)!.path;
  await Bun.file(target).delete();
  await Bun.write(target, "");
  console.log(
    JSON.stringify({
      status: "submitted",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
        api_token: "highly-secret",
      },
    }),
  );
} else if (mode === "delayed") {
  await Bun.sleep(50);
  console.log(
    JSON.stringify({
      status: "submitted",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
        api_token: "highly-secret",
      },
    }),
  );
} else if (mode === "late") {
  await Bun.sleep(200);
  console.log(
    JSON.stringify({
      status: "submitted",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
        api_token: "highly-secret",
      },
    }),
  );
} else if (mode === "block") {
  const marker = process.env.KEY_KONG_FAKE_MARKER;
  if (marker) {
    process.on("SIGTERM", async () => {
      await Bun.write(marker, "terminated");
      process.exit(0);
    });
  }
  const ready = process.env.KEY_KONG_FAKE_READY;
  if (ready) {
    await Bun.write(ready, "ready");
  }
  await Bun.sleep(5_000);
} else {
  console.log(
    JSON.stringify({
      status: "submitted",
      values: {
        environment: "prod",
        region: "us-west-2",
        features: ["audit", "alerts"],
        api_token: "highly-secret",
      },
    }),
  );
}
