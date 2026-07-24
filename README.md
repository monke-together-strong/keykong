# Key Kong

A secure, blocking input broker for agent skills and manual workflows.

It presents desktop prompts, shows the resolved destination, routes submitted
values according to a broker-validated delivery specification, and returns only
non-secret responses plus a machine-readable outcome. This keeps secrets out of
model context, logs, and tool responses.

The current release targets macOS and uses a one-shot Bun CLI with a private
native AppKit prompt sidecar.

## Build and run

Install dependencies and run the complete test suite:

```sh
bun install
bun run test
bun run test:swift
```

Build the self-contained signed macOS layout in `dist/`:

```sh
bun run package:macos
```

`KEY_KONG_CODESIGN_IDENTITY` may select a Developer ID identity; without it the
script applies an ad-hoc signature. The public executable is
`dist/bin/key-kong`, and its compatible private helper is
`dist/libexec/key-kong-prompt`.

Submit a versioned JSON request from a file or explicit standard input:

```sh
dist/bin/key-kong request request.json
producer | dist/bin/key-kong request -
```

See [the request schema](docs/request-schema.md) for supported response and
secret fields, ordered file deliveries, and the result shape.

The CLI also provides `schema`, `--help`, and `--version`. The `request`
command writes exactly one newline-terminated JSON object to standard output.

## Architecture

Bun owns request decoding and validation, the ten-minute whole-request deadline,
prompt projection, submission validation, ordered file delivery, result
shaping, and exit behavior. The Swift executable receives presentation-only
JSON on standard input and returns one submission or cancellation JSON object
on standard output. Submitted values never travel through command arguments,
environment variables, temporary files, diagnostics, or logs.
