import { requestCommand, type Execution } from "./command";
import { Deadline } from "./deadline";
import { ExpiredError, KeyKongError } from "./errors";
import { requestSchema } from "./schema";

declare const KEY_KONG_TESTING: boolean;

const help = `Key Kong 1.0.0

Usage:
  key-kong request <file|->
  key-kong schema
  key-kong --help
  key-kong --version
`;

function timeoutSeconds() {
  if (KEY_KONG_TESTING) {
    const configured = Number(process.env.KEY_KONG_TEST_TIMEOUT_SECONDS);
    if (Number.isFinite(configured)) return Math.min(600, Math.max(0.01, configured));
  }
  return 600;
}

function failure(error: unknown): Execution {
  if (error instanceof ExpiredError) {
    return { result: { status: "expired", values: {} }, exitCode: 1 };
  }
  if (error instanceof KeyKongError) {
    return {
      result: {
        status: "failed",
        values: {},
        error: { code: error.code, message: error.message },
      },
      exitCode: error.exitCode,
      diagnostic: error.message,
    };
  }
  return {
    result: {
      status: "failed",
      values: {},
      error: { code: "INTERNAL_FAILURE", message: "unexpected internal failure" },
    },
    exitCode: 1,
    diagnostic: "unexpected internal failure",
  };
}

const args = process.argv.slice(2);
if (args.length === 1 && args[0] === "schema") {
  console.log(JSON.stringify(requestSchema));
  process.exit(0);
}
if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) {
  process.stdout.write(help);
  process.exit(0);
}
if (args.length === 1 && args[0] === "--version") {
  console.log("key-kong 1.0.0");
  process.exit(0);
}

const requestTimeout = timeoutSeconds();
const processDeadline = new Deadline(requestTimeout);
const outputMargin = Math.min(0.25, requestTimeout / 2);
const workDeadline = new Deadline(requestTimeout - outputMargin);
let execution: Execution;
try {
  if (
    KEY_KONG_TESTING &&
    process.env.KEY_KONG_TEST_FORCE_INTERNAL_FAILURE === "1"
  ) {
    throw new Error("test-only internal failure");
  }
  execution = await requestCommand(args, workDeadline);
} catch (error) {
  execution = failure(error);
}
try {
  await processDeadline.race(
    Bun.write(Bun.stdout, `${JSON.stringify(execution.result)}\n`),
  );
  if (execution.diagnostic) {
    await processDeadline.race(
      Bun.write(Bun.stderr, `${execution.diagnostic}\n`),
    );
  }
  process.exit(execution.exitCode);
} catch (error) {
  process.exit(error instanceof ExpiredError ? 1 : execution.exitCode);
}
