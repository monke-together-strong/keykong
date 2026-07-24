#!/usr/bin/env bun

export {};

const marker = process.env.KEY_KONG_FAKE_MARKER;
if (marker) await Bun.write(marker, "launched");

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
  case "cancel":
    console.log('{"status":"cancelled"}');
    break;
  case "malformed":
    console.log("not-json");
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
