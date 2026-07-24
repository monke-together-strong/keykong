# Key Kong

A secure, blocking input broker for agent skills and manual workflows.

The current migration slice targets macOS and adds a one-shot Bun CLI with a
private native AppKit Prompt Adapter. The established Swift CLI remains
available as a fallback while the Bun path expands.

## Build and run

Install dependencies and run both test suites:

```sh
bun install
bun run test
bun run test:swift
```

Build the Bun CLI and its private helper layout in `dist/`, or build the legacy
Swift CLI fallback:

```sh
bun run build
bun run build:helper
bun run build:legacy
```

The public Bun executable is `dist/bin/key-kong`, and its compatible private
helper is `dist/libexec/key-kong-prompt`.

Submit a versioned JSON request from a file or explicit standard input:

```sh
dist/bin/key-kong request request.json
producer | dist/bin/key-kong request -
```

The CLI also provides `schema`, `--help`, and `--version`. The `request`
command writes exactly one newline-terminated JSON object to standard output.

See [the request schema](docs/request-schema.md) for the versioned contract.
This slice executes response-only requests with required text, single-select,
and multi-select fields. Secret delivery and filesystem behavior remain with
the fallback until the next migration slice.

## Architecture

Bun owns response-request decoding and validation, prompt projection, submission
validation, result shaping, and exit behavior. The Swift executable receives
presentation-only JSON on standard input and returns one submission or
cancellation JSON object on standard output. The protocol already represents
secret fields and sanitized delivery details without giving the Prompt Adapter
delivery behavior.
