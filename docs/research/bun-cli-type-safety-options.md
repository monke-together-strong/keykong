# Type-safe CLI options for the Bun rewrite

## Question

Should Key Kong use Zod and Commander for its Bun CLI, or is there a more modern
type-safe stack that better fits an agent-facing, one-request-per-process
command?

## Recommendation

Use:

- **Zod 4** as the source of truth for request and result schemas.
- **Commander 15 through `@commander-js/extra-typings`** for CLI commands,
  operands, help, and version handling.
- **Bun's runtime and compiler** for execution and distribution.

This is the smallest stack that gives Key Kong runtime validation, inferred
TypeScript types, generated JSON Schema, strongly typed command handlers, and
standard CLI help without introducing a larger application framework.

```sh
bun add zod commander @commander-js/extra-typings
```

`@commander-js/extra-typings` is maintained under the Commander organization and
adds inferred types for `.opts()` and `.action()` parameters. Its current
package declares Commander 15 as a peer dependency.
[Commander TypeScript documentation](https://github.com/tj/commander.js/#typescript),
[`extra-typings` package manifest](https://raw.githubusercontent.com/commander-js/extra-typings/main/package.json)

Zod 4 is stable, infers TypeScript types from runtime schemas, and now converts
schemas to JSON Schema natively with `z.toJSONSchema()`. It supports Draft
2020-12 output, which means the same schema can validate incoming requests,
provide `z.infer` application types, and implement `key-kong schema`.
[Zod 4](https://zod.dev/packages/zod),
[Zod JSON Schema conversion](https://zod.dev/json-schema)

## Suggested shape

Keep CLI parsing and document validation separate:

```ts
import { Command } from "@commander-js/extra-typings";
import * as z from "zod";

export const RequestSchema = z.strictObject({
  schemaVersion: z.literal(1),
  id: z.string().min(1),
  title: z.string().min(1),
  fields: z.array(FieldSchema).min(1),
  deliveries: z.array(DeliverySchema),
});

export type Request = z.infer<typeof RequestSchema>;

const program = new Command()
  .name("key-kong")
  .version(version);

program
  .command("request")
  .argument("<file|->")
  .action(async (source) => {
    const document = await readRequest(source);
    const request = RequestSchema.parse(document);
    await executeRequest(request);
  });

program
  .command("schema")
  .action(() => {
    process.stdout.write(
      JSON.stringify(
        z.toJSONSchema(RequestSchema, {
          target: "draft-2020-12",
          io: "input",
        }),
      ) + "\n",
    );
  });
```

Use `z.strictObject()` at external boundaries so unknown request properties are
rejected rather than silently ignored. Keep the exported request schema free of
Zod transforms and other types that Zod documents as unrepresentable in JSON
Schema.

Define the caller-facing result as a Zod discriminated union too. Route every
result through one output function that validates it before writing exactly one
JSON object to stdout. This prevents a code change from silently violating the
agent contract.

Commander should only parse CLI syntax. Zod should validate the JSON document
and native-sidecar response. Avoid duplicating the request shape in Commander
options.

## Alternatives

### `@stricli/core`

Stricli is the best alternative if compile-time CLI argument typing is the top
priority. It infers parser definitions from command implementation types,
supports flags and positional arguments, has no runtime dependencies, includes
dependency-injection support and dynamic completion, and publishes
assistant-oriented documentation. It requires TypeScript `strict` mode for its
conditional-type inference.
[Stricli overview](https://bloomberg.github.io/stricli/),
[argument parsing](https://bloomberg.github.io/stricli/docs/features/argument-parsing),
[package manifest](https://raw.githubusercontent.com/bloomberg/stricli/main/packages/core/package.json)

It does not replace Zod for nested JSON request validation. For Key Kong's small
surface—`request`, `schema`, `--help`, and `--version`—its route-map and
command-definition model buys little over Commander with extra typings. Choose
Stricli if the CLI is expected to grow into a large command tree with completion
and lazy-loaded commands.

### Bun `util.parseArgs`

Bun officially recommends the Node-compatible `util.parseArgs` API for basic
argument parsing. It is dependency-free and sufficient for a single command,
but subcommand routing, help text, version output, error formatting, and command
documentation remain application code.
[Bun argument parsing](https://bun.sh/docs/guides/process/argv)

This is viable if minimizing dependencies outweighs maintaining those small
utilities. Commander is the simpler choice once multiple public commands exist.

### Clipanion

Clipanion is full-featured, type-safe, and designed to prevent code from relying
on options that are no longer declared. It supports nested commands and strong
option typing.
[Clipanion overview](https://mael.dev/clipanion/docs/)

Its class-oriented, full-framework model is more machinery than Key Kong needs,
and it offers no advantage over Zod for the JSON request boundary.

### Effect CLI

`@effect/cli` supplies typed arguments, options, commands, validation errors,
configuration, prompts, and an Effect-native runtime model. Effect also has a
Bun platform package.
[`@effect/cli` API](https://effect-ts.github.io/effect/docs/cli)

It is attractive only if Key Kong deliberately adopts Effect throughout its
core. Introducing Effect solely to parse four CLI entry points would expand the
programming model and dependency surface without improving the request/response
contract.

### oclif

oclif is appropriate for a large extensible CLI with generators, hooks,
installable plugins, and update infrastructure. Its official support target is
Node.js LTS rather than Bun.
[oclif introduction and requirements](https://oclif.io/docs/introduction/)

Those capabilities are out of scope for a one-shot Bun executable and would
reintroduce the framework complexity the native sidecar design intentionally
avoids.

## Bun packaging

Bun can compile a TypeScript entry point and its JavaScript dependencies into a
standalone executable. Commander, extra typings, and Zod are ordinary
JavaScript/TypeScript packages with no native addon requirement, so they fit
that packaging model; the final implementation should still include a compiled
binary smoke test in CI.
[Bun standalone executables](https://bun.sh/docs/bundler#executables)

## Decision rule

- Choose **Zod 4 + Commander extra typings** for Key Kong now.
- Choose **Zod 4 + Stricli** only if the command tree is expected to become a
  substantial product surface.
- Choose **Bun `util.parseArgs` + Zod 4** only if zero CLI dependencies is a
  stronger priority than generated help and command ergonomics.
- Do not choose Effect CLI or oclif unless the surrounding application adopts
  the broader framework they are designed to provide.
