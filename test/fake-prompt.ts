#!/usr/bin/env bun

export {};

const marker = process.env.KEY_KONG_FAKE_MARKER;
if (marker) await Bun.write(marker, "launched");

const request = JSON.parse(await Bun.stdin.text());
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

if (
  request.title !== "Deploy" ||
  JSON.stringify(request.fields) !== JSON.stringify(expectedFields) ||
  JSON.stringify(request.deliveries) !== "[]"
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
  default:
    console.log(
      JSON.stringify({
        status: "submitted",
        values: {
          environment: "prod",
          region: "us-west-2",
          features: ["alerts", "audit"],
        },
      }),
    );
}
