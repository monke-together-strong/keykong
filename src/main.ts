import { requestCommand, type Execution } from "./command";
import { Deadline, DeadlineExpired } from "./deadline";
import { KeyKongError } from "./errors";
import { requestSchema } from "./schema";

const help = `Key Kong 1.0.0

Usage:
  key-kong request <file|->
  key-kong schema
  key-kong --help
  key-kong --version
`;

declare const KEY_KONG_TESTING: boolean;

function failure(error: unknown): Execution {
  if (error instanceof DeadlineExpired) {
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
    };
  }
  return {
    result: {
      status: "failed",
      values: {},
      error: {
        code: "INTERNAL_FAILURE",
        message: "unexpected internal failure",
      },
    },
    exitCode: 1,
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

const configuredTimeout = KEY_KONG_TESTING
  ? Number(process.env.KEY_KONG_TEST_DEADLINE_MS) || 10 * 60 * 1_000
  : 10 * 60 * 1_000;
const processDeadline = new Deadline(configuredTimeout);
const outputMarginMS = Math.min(250, configuredTimeout / 2);
const workDeadline = new Deadline(configuredTimeout - outputMarginMS);

let execution: Execution;
try {
  execution = await requestCommand(args, workDeadline);
} catch (error) {
  execution = failure(error);
}
const output = `${JSON.stringify(execution.result)}\n`;
try {
  await processDeadline.run(Bun.write(Bun.stdout, output));
  if (execution.result.error) {
    await processDeadline.run(
      Bun.write(Bun.stderr, `${execution.result.error.message}\n`),
    );
  }
} catch (error) {
  if (error instanceof DeadlineExpired) process.exit(1);
  throw error;
}
process.exit(execution.exitCode);
