# Key Kong

A secure, blocking input broker for agent skills and manual workflows.

It presents desktop prompts, routes submitted values directly to a pre-approved destination, and returns only completion status to the caller. This keeps secrets out of model context, logs, and tool responses.

The first prototype targets macOS only and uses a native multi-field dialog. Windows is out of scope for now.

## Build and run

Build the CLI with Swift Package Manager:

```sh
swift build
```

Then submit a JSON request from a file or standard input:

```sh
.build/debug/key-kong request --request request.json
producer | .build/debug/key-kong request --request -
```

See [the request schema](docs/request-schema.md) for supported response and
secret fields, ordered file deliveries, and the result shape.

## Native dialog demo

Run `swift demo/KeyKongDemo.swift` on macOS to open a two-field native prompt. It is a UI-only demo: submitted values are never printed or persisted.
