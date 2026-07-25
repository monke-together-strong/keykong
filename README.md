# Key Kong

A secure, blocking input Broker for agent skills and manual workflows.

The shipped macOS architecture is one Bun package and one Swift package. Bun
provides the sole public `key-kong` executable; Swift provides only the private,
one-shot AppKit Prompt Adapter packaged as an application bundle.

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

The public Bun executable is `dist/bin/key-kong`. Its compatible private helper
is:

```text
dist/libexec/KeyKongPrompt.app/
└── Contents/
    ├── Info.plist
    └── MacOS/
        └── key-kong-prompt
```

The bundle is not installed in `/Applications`; Bun launches its nested
executable from this fixed location. Packaging uses an ad-hoc signature by
default. Set `KEY_KONG_SIGNING_IDENTITY` to a signing identity for release
artifacts. Packaging signs the nested helper before the app container, signs the
CLI separately, and strictly verifies all three.

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
helper process. While input is pending, the private app has regular macOS
activation behavior: `KeyKong` appears in the Dock and Command-Tab, its window
can be covered or miniaturized, and reactivation restores the same prompt
without creating another. The window is not permanently floating.

The application bundle supplies the stable Launch Services identity required
for that discoverability; it does not turn the adapter into a daemon or a public
application. There is no FFI boundary, plugin registry, request history, or
retained submitted value after the terminal result is produced.
