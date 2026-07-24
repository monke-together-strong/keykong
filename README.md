# Key Kong

A secure, blocking input broker for agent skills and manual workflows.

It presents desktop prompts, routes submitted values directly to a pre-approved destination, and returns only completion status to the caller. This keeps secrets out of model context, logs, and tool responses.

## Native dialog demo

Run `swift demo/KeyKongDemo.swift` on macOS to open a two-field native prompt. It is a UI-only demo: submitted values are never printed or persisted.
