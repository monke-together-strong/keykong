import { requestCommand, type Execution } from "./command";
import { KeyKongError } from "./errors";
import { requestSchema } from "./schema";

const help = `Key Kong 1.0.0

Usage:
  key-kong request <file|->
  key-kong schema
  key-kong --help
  key-kong --version
`;

function failure(error: unknown): Execution {
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
      error: { code: "PROMPT_FAILED", message: "native prompt failed" },
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

let execution: Execution;
try {
  execution = await requestCommand(args);
} catch (error) {
  execution = failure(error);
}
process.stdout.write(`${JSON.stringify(execution.result)}\n`);
process.exit(execution.exitCode);
