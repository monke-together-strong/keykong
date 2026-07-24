#!/usr/bin/env bun

export {};

const marker = process.env.KEY_KONG_FAKE_MARKER;
if (marker) await Bun.write(marker, "launched");
const pidMarker = process.env.KEY_KONG_FAKE_PID_MARKER;
if (pidMarker) await Bun.write(pidMarker, String(process.pid));

const request = JSON.parse(await Bun.stdin.text());
if (
  request.deliveries.some(
    (delivery: Record<string, unknown>) =>
      "template" in delivery ||
      "id" in delivery ||
      !("path" in delivery) ||
      !("operation" in delivery),
  )
) {
  process.exit(9);
}
const expectedFields = [
  {
    id: "environment",
    label: "Environment",
    type: "text",
  },
  {
    id: "region",
    label: "Region",
    type: "select",
    options: [{ label: "Oregon", value: "us-west-2" }],
  },
  {
    id: "features",
    label: "Features",
    type: "multi_select",
    options: [
      { label: "Audit", value: "audit" },
      { label: "Alerts", value: "alerts" },
    ],
  },
];

const deliveryFields = [
  ...expectedFields,
  { id: "api_token", label: "API token", type: "secret" },
];
if (
  !(
    (request.title === "Deploy" &&
      JSON.stringify(request.fields) === JSON.stringify(expectedFields) &&
      JSON.stringify(request.deliveries) === "[]") ||
    (request.title === "Deploy secret" &&
      JSON.stringify(request.fields) === JSON.stringify(deliveryFields))
  )
) {
  process.exit(9);
}

switch (process.env.KEY_KONG_FAKE_MODE) {
  case "block":
    await new Promise(() => {});
    break;
  case "resist_termination":
    process.on("SIGTERM", () => {});
    await new Promise(() => {});
    break;
  case "late":
    await Bun.sleep(500);
  case "cancel":
    console.log('{"status":"cancelled"}');
    break;
  case "cancel_nonzero":
    console.log('{"status":"cancelled"}');
    process.exit(9);
  case "malformed":
    console.log("raw-native-secret");
    break;
  case "extra":
    console.log('{"status":"cancelled"}\nraw-native-secret');
    break;
  case "eof":
    break;
  case "nonzero":
    console.error("raw-native-secret");
    process.exit(9);
  case "crash":
    process.kill(process.pid, "SIGKILL");
    break;
  case "large":
    console.log(
      JSON.stringify({
        status: "submitted",
        values: {
          environment: "x".repeat(1024 * 1024),
          region: "us-west-2",
          features: ["audit", "alerts"],
        },
      }),
    );
    break;
  case "empty":
    console.log(
      JSON.stringify({
        status: "submitted",
        values: {
          environment: "",
          region: "us-west-2",
          features: ["audit"],
          ...(request.title === "Deploy secret" ? { api_token: "" } : {}),
        },
      }),
    );
    break;
  case "replace_last": {
    const target = request.deliveries.at(-1).path;
    await Bun.file(target).delete();
    await Bun.write(target, "");
    console.log(
      JSON.stringify({
        status: "submitted",
        values: {
          environment: "prod",
          region: "us-west-2",
          features: ["alerts", "audit"],
          api_token: "highly-secret",
        },
      }),
    );
    break;
  }
  default:
    console.log(
      JSON.stringify({
        status: "submitted",
        values: {
          environment: "prod",
          region: "us-west-2",
          features: ["alerts", "audit"],
          ...(request.title === "Deploy secret"
            ? { api_token: "highly-secret" }
            : {}),
        },
      }),
    );
}
