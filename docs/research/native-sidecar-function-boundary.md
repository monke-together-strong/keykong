# Native sidecar as a function boundary

## Question

What is the minimal pattern for letting a Bun application call native UI when
that UI cannot run in the Bun process itself?

## Conclusion

Treat the native helper as an out-of-process function:

```text
response = await nativePrompt(request)
```

The macOS implementation of `nativePrompt` does only this:

1. Bun launches the bundled Swift executable.
2. Bun writes one JSON request to the child's standard input and closes it.
3. Swift reads the request, displays native AppKit UI, and waits for the user.
4. Swift writes one JSON response to standard output and exits.
5. Bun reads the response and continues exactly as it would after an in-process
   native function returned.

Because there is exactly one request and one response per process, end-of-file
is sufficient framing: closing stdin terminates the request, and process exit
terminates the response. A length prefix, request ID, handshake, socket, daemon,
adapter registry, or plugin system is unnecessary for this v1 shape.

Bun already exposes the required primitives: `Bun.spawn()` accepts a command as
an argument array, supports piped stdin, exposes stdout and stderr as streams,
reports process exit, and supports cancellation and timeouts.
[Bun child-process documentation](https://bun.sh/docs/runtime/child-process)

Swift Foundation exposes the corresponding standard input, output, and error
handles through `FileHandle.standardInput`, `standardOutput`, and
`standardError`.
[Apple `standardInput`](https://developer.apple.com/documentation/foundation/filehandle/standardinput),
[Apple `standardOutput`](https://developer.apple.com/documentation/foundation/filehandle/standardoutput),
[Apple `standardError`](https://developer.apple.com/documentation/foundation/filehandle/standarderror)

## Minimal interface

The protocol should describe the native operation, not the rest of the
application:

```ts
type NativePromptRequest = {
  title: string;
  fields: Array<{
    id: string;
    label: string;
    type: "text" | "secret" | "select" | "multi_select";
    options?: Array<{
      label: string;
      value: string;
    }>;
  }>;
  deliveries: Array<{
    path: string;
    operation: "append" | "insert_line";
    line?: number;
  }>;
};

type NativePromptResponse =
  | {
      status: "submitted";
      values: Record<string, string | string[]>;
    }
  | { status: "cancelled" };
```

The exact schema can grow when the native UI needs another argument or result,
just as an ordinary function signature would. It does not need to anticipate
Windows, web, third-party adapters, or independently versioned helpers. Bun
derives this presentation model from the validated application request:
delivery templates and execution objects never cross the native boundary, while
the sanitized paths and operations needed by the existing Details view do.

## Transport rules

The small amount of discipline needed around the function boundary is:

- Launch the executable directly with `Bun.spawn([helperPath])`; do not route
  through a shell.
- Configure stdin, stdout, and stderr as pipes. Do not inherit stdout, because
  the response contains submitted values.
- Reserve stdout exclusively for the JSON response. Send scrubbed diagnostics
  to stderr and never log submitted values.
- Close stdin after writing the request, read stdout to EOF, check the exit
  status, and treat malformed JSON, premature exit, or timeout as a failed
  native call.
- Spawn one helper for one prompt. Terminate it if the Bun-side operation is
  cancelled or times out.

Chrome Native Messaging is a first-party precedent for the same process shape:
Chrome launches a native program, exchanges JSON through stdin and stdout,
keeps diagnostics on stderr, and its one-message API launches one process and
uses the first message as the response. Chrome uses a length prefix because its
protocol also supports persistent multi-message ports; Key Kong's one-shot
process does not need that additional framing.
[Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

Tauri likewise documents bundled executables written in any language as
"sidecars" and demonstrates communicating with them through stdin and stdout.
Its per-target binary packaging is evidence that the helper is an ordinary
platform build artifact, not a JavaScript package.
[Tauri external binaries](https://v2.tauri.app/develop/sidecar/)

## Packaging

For macOS, ship a self-contained CLI distribution:

```text
key-kong/
├── bin/
│   └── key-kong
└── libexec/
    └── KeyKongPrompt.app/
        └── Contents/
            ├── Info.plist
            └── MacOS/
                └── key-kong-prompt
```

Compile Bun into the public CLI executable and Swift into the private app-bundle
helper. The CLI resolves the nested executable from its own installation and
never searches `PATH`. The bundle gives the one-shot helper a stable Launch
Services identity and regular application activation behavior; it does not make
the helper a launcher, menu-bar process, or daemon. Sign the nested helper, app
container, and public CLI for release.

A future Windows build can replace the Swift executable with a Windows-native
executable that implements the same JSON input/output behavior. That is a new
implementation of the function, not a reason to generalize the macOS code
today. Tauri's sidecar documentation shows the same general packaging pattern
with target-specific binaries, including Windows `.exe` files.
[Tauri external binaries](https://v2.tauri.app/develop/sidecar/)

## What remains in Bun

Everything that would remain outside an in-process native UI function also
remains outside the sidecar:

- request construction and application-level validation;
- deciding when to prompt;
- deciding what to do with submitted values;
- delivery, persistence, or other business behavior;
- translating the native result into the caller-facing result.

Therefore sink definitions, destination approval, and delivery policy are
orthogonal to the native boundary. They may be legitimate product questions,
but the sidecar pattern neither requires nor answers them. The helper merely
replaces an unavailable in-process native UI call with a private request and
response over child-process pipes.

## Testing boundary

Favor end-to-end tests that launch the built CLI, provide a complete JSON
request, observe delivery side effects, and assert the exit code plus exact JSON
result. Exercise completed, partial, failed, cancelled, expired,
invalid-request, and secret non-disclosure behavior through this public
boundary.

The prompt helper path is the one deliberate test seam. Most CLI tests use a
small fake executable that implements the same one-request/one-response pipe
contract, allowing unattended submission, cancellation, malformed-response,
crash, and timeout scenarios without splitting Bun internals into separately
mocked units.

Keep only a few focused Swift tests for behavior that the fake helper cannot
prove: rendering every field kind, returning stable option values rather than
labels, masking and clearing secret input, showing sanitized delivery details,
and cancelling the native form. A small contract check also ensures the real
helper decodes the request and encodes the response expected by Bun.

## Future web implementation

A web implementation can conform to the same logical
`nativePrompt(request) -> response` interface, but it will not necessarily use
the child-process transport. Its transport depends on whether it runs in an
embedded WebView, local browser page, extension, or hosted page. No web
transport needs to be chosen for the macOS implementation.
