# Key Kong

A secure, blocking input Broker for agent skills and manual workflows.

The shipped macOS architecture is one Bun package and one Swift package. Bun
provides the sole public `key-kong` executable; Swift provides only the private,
one-shot AppKit Prompt Adapter.

## Build and run

Install dependencies and run both test suites:

```sh
bun install
bun run test
bun run test:swift
```

Build and sign the self-contained macOS layout in `dist/`:

```sh
bun run package:macos
```

The public Bun executable is `dist/bin/key-kong`, and its compatible private
helper is `dist/libexec/key-kong-prompt`. Packaging uses an ad-hoc signature by
default. Set `KEY_KONG_SIGNING_IDENTITY` to a signing identity for release
artifacts; both executables are verified after signing.

Submit a versioned JSON request from a file or explicit standard input:

```sh
dist/bin/key-kong request request.json
producer | dist/bin/key-kong request -
```

The CLI also provides `schema`, `--help`, and `--version`. Requests require
`schemaVersion: 1`, and the `request` command writes exactly one
newline-terminated JSON result to standard output.

See [the request schema](docs/request-schema.md) for the versioned contract.
The Bun path supports required text, secret, single-select, and multi-select
fields plus ordered append and insert-before-line deliveries to existing
absolute-path files.

## Architecture

Bun is the Broker. It owns the ten-minute whole-request deadline, request
decoding, authoritative request and submission validation, prompt projection,
template rendering, filesystem delivery, result shaping, and exit behavior.
The Swift Prompt Adapter provides immediate required-field feedback in the UI,
receives presentation-only JSON on standard input, and returns one submission
or cancellation JSON object on standard output. It sees sanitized delivery
paths, operations, and insertion lines, but never templates or delivery
behavior.

Each invocation is one Bun process and, when prompting is needed, one Swift
helper process. There is no daemon, FFI boundary, plugin registry, request
history, or retained submitted value after the terminal result is produced.
