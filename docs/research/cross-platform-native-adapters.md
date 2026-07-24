# Cross-platform Prompt Adapter architecture

> **Scope correction:** This survey explores several broader platform patterns,
> but Key Kong v1 needs only the smaller function boundary documented in
> [Native sidecar as a function boundary](./native-sidecar-function-boundary.md).
> The macOS helper receives one JSON request, returns one JSON response, and
> exits. Version negotiation, length-prefixed framing, adapter registries, and
> unimplemented Windows or web projects are not part of v1.

## Question

How are applications usually structured when shared orchestration code must use
different native implementations on macOS and Windows, while also supporting a
web-based prompt?

## Conclusion

The useful pattern is a **trusted Broker calling native presentation through a
function-shaped boundary**:

1. A single Broker owns request validation, lifecycle, policy, and delivery.
2. The macOS implementation runs as a bundled helper process.
3. Bun sends it one prompt request and privately receives one prompt response.
4. A future platform may implement the same logical function using a different
   transport, without requiring that transport to be designed now.

For Key Kong, the Broker should run in Bun. It may hold submitted values
transiently in memory, but it must not expose them to the invoking caller,
stdout, logs, command arguments, environment variables, or persistent storage.
The Swift, Windows, and web implementations should own presentation—not sink
delivery. Centralizing delivery avoids duplicating security-sensitive sink logic
across every platform.

This shape is more conventional and maintainable than either calling native UI
frameworks directly through FFI or turning every native helper into a complete
independent Broker.

## What established systems do

### 1. Put privileged behavior in a Broker-shaped process

Electron separates its privileged main process from renderer processes. The
main process owns application lifecycle and native desktop APIs, while renderers
behave as web pages. Electron recommends exposing a narrow API to renderers
through a preload script and `contextBridge`, rather than giving renderer code
unrestricted Node access. This is the same broad trust shape Key Kong needs:
untrusted caller outside, trusted Broker in the middle, and a constrained UI
surface.
Source: [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)

Tauri makes the division even more explicit: a Core process manages global
state and routes IPC centrally, while WebView processes render UI. Tauri uses
serialized asynchronous message passing and describes it as safer than shared
memory or direct function access because the recipient can validate and reject
requests. Its capability system constrains which commands a particular window
or WebView may invoke.
Sources: [Tauri process model](https://v2.tauri.app/concept/process-model/),
[Tauri IPC](https://v2.tauri.app/concept/inter-process-communication/),
[Tauri capabilities](https://v2.tauri.app/security/capabilities/)

**Implication for Key Kong:** Bun should host the privileged Broker. Prompt
implementations should receive only the operations and data necessary to render
and complete a prompt. Sink execution should remain in the Broker.

### 2. Define one interface and implement it per platform

Flutter calls this the federated plugin pattern. It separates an app-facing
interface, a platform interface, and individual platform implementations. A
macOS implementation and a Windows implementation can therefore be separate
packages while remaining substitutable behind one contract. Flutter platform
channels carry asynchronous messages between shared code and host-platform
code.
Sources: [Flutter federated plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages),
[Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)

React Native follows a similar specification-first model. A typed specification
defines the expected native module API, and code generation produces
platform-specific scaffolding. React Native for Windows documents the same
sequence: define the API in TypeScript, generate native headers, implement the
Windows code, and register it.
Sources: [React Native Codegen](https://reactnative.dev/docs/the-new-architecture/what-is-codegen),
[React Native Windows native modules](https://microsoft.github.io/react-native-windows/docs/native-platform-modules/)

**Implication for Key Kong:** define a small `PromptAdapter` protocol
independently of Swift, C#, or browser APIs. Keep the protocol as the source of
truth and test every implementation against the same fixtures. JSON Schema is a
reasonable source format because it is language-neutral and the transport is
already message-based.

### 3. Package native integrations as sidecar executables

Tauri officially supports bundled external binaries, calling them sidecars.
Sidecars can be written in any language, are packaged per target architecture,
and can communicate over stdin and stdout. Tauri also requires explicit
capabilities to permit a sidecar to run.
Source: [Tauri external binaries](https://v2.tauri.app/develop/sidecar/)

Chrome Native Messaging uses almost exactly this architecture for browser-to-
desktop integration. Chrome launches a registered native host as a separate
process and exchanges length-prefixed JSON over stdin and stdout. Access is
limited to explicitly allowed extension origins. Chrome also requires stdout to
contain protocol messages only, with diagnostics sent elsewhere.
Source: [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

Git credential helpers are another long-lived example. Git invokes external
helper programs and exchanges credential attributes over a defined stdin/stdout
protocol, allowing platform-specific storage or acquisition implementations
behind a stable interface.
Sources: [Git credentials](https://git-scm.com/docs/gitcredentials.html),
[Git credentials API](https://git-scm.com/docs/api-credentials)

Bun supports spawning child processes with piped stdin/stdout and timeout or
abort handling. Its direct IPC serialization is specifically documented for
Bun/Node children, so language-neutral native helpers should use ordinary pipes
or a socket instead.
Source: [Bun child processes](https://bun.sh/docs/runtime/child-process)

**Implication for Key Kong:** compile the Swift and Windows Prompt Adapters as helper
executables, bundle the correct binary in each distribution, and launch them
directly from Bun without a shell. Start with one helper per request; introduce
a persistent service only if startup latency or OS lifecycle behavior proves it
necessary.

### 4. FFI is useful, but is a poor default boundary here

Electron supports in-process native addons, but its documentation highlights
runtime ABI and rebuild requirements. Bun's own documentation currently labels
`bun:ffi` experimental and says it has known bugs and limitations; it recommends
Node-API as the more stable production route.
Sources: [Electron native modules](https://www.electronjs.org/docs/latest/tutorial/using-native-node-modules/),
[Bun FFI](https://bun.sh/docs/runtime/ffi),
[Node-API](https://nodejs.org/api/n-api.html)

FFI also couples native UI lifecycle, main-thread requirements, crashes, and
memory ownership to the Bun process. A sidecar failure can instead be converted
into a controlled `failed` status.

**Implication for Key Kong:** prefer helper processes over FFI. Reconsider FFI
only for a narrow, stable C ABI where process isolation provides no value.

## A web Prompt Adapter is three different products

“Web prompt” needs a precise meaning:

### Embedded WebView

The HTML/CSS/JavaScript prompt is bundled inside a desktop application and
rendered by the operating system WebView. It talks to the local Broker through
a constrained application IPC bridge. This follows the Tauri/Electron model and
can be treated as another local `PromptAdapter`.

This option is cross-platform, but it is not an OS-native dialog. Native
password controls may be more consistent with platform accessibility, focus,
window activation, and user expectations.

### Browser extension

An installed extension can talk to a registered local companion through the
browser's Native Messaging facility. This is the conventional way for a browser
surface to reach privileged local code. The extension and native-host installer
become additional signed and versioned deliverables.

Chrome's API is permissioned and available to extension contexts, not ordinary
webpage JavaScript. The native-host manifest explicitly allowlists extension
origins.
Source: [Chrome Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)

### Hosted webpage

An ordinary HTTPS webpage can collect a value with an HTML password control,
whose standard behavior obscures entry, and can submit it to a remote HTTPS
service. It does not receive the privileged bridge available to an embedded
WebView or browser extension.
Source: [HTML password state](https://html.spec.whatwg.org/multipage/input.html#password-state-(type=password))

A hosted page therefore cannot be a drop-in implementation for Key Kong's
declared **local** sinks unless an installed companion and authenticated local
transport are added. If it sends values to a remote service, that changes the
trust model and product boundary rather than merely changing the prompt UI.

## Recommended Key Kong model

```text
Invoking process
      |
      | request without submitted values
      v
+-----------------------------+
| Trusted Bun Broker          |
| - validates request         |
| - selects Prompt Adapter    |
| - enforces timeout/cancel   |
| - performs delivery         |
| - returns safe result       |
+-----------------------------+
      ^                 |
      | submitted       | prompt request
      | values          v
+-----------------------------+
| Prompt Adapter              |
| macOS / Windows / WebView   |
+-----------------------------+
```

Recommended Prompt Adapters:

- `macos-native`: Swift and AppKit, using `NSSecureTextField` for secret
  fields. Apple describes it as the AppKit control intended for secret entry.
  [Apple `NSSecureTextField`](https://developer.apple.com/documentation/appkit/nssecuretextfield)
- `windows-native`: C# with Windows App SDK/WinUI, using `PasswordBox` for
  masked input.
  [Microsoft `PasswordBox`](https://learn.microsoft.com/windows/apps/develop/ui/controls/password-box)
- `webview`: bundled HTML/CSS/JavaScript rendered locally and connected through
  a constrained bridge.
- `browser-extension`: optional later Prompt Adapter using Native Messaging.
- A hosted web application should be treated as a separate deployment model,
  not silently registered as equivalent to a local Prompt Adapter.

## Function shape

Keep the native call narrower than the external request schema. The helper does
not need to know how sinks work.

Bun to Swift:

```json
{
  "title": "Credentials needed",
  "fields": [
    {
      "id": "github-token",
      "label": "GitHub token",
      "type": "secret"
    }
  ],
  "deliveries": [
    {
      "path": "/absolute/path/to/existing.env",
      "operation": "append"
    }
  ]
}
```

Swift to Bun:

```json
{
  "status": "submitted",
  "values": {
    "github-token": "sensitive value"
  }
}
```

The helper's other response is `cancelled`, without a `values` member. Bun owns
expiry and failure outcomes.

For a one-request helper, EOF is sufficient framing. Bun writes one JSON value
and closes stdin; Swift writes one JSON value and exits. Request IDs, length
prefixes, handshakes, sockets, and version negotiation solve multi-message or
independent-versioning problems that this bundled one-shot helper does not have.

Security requirements for the bridge:

- Spawn an exact packaged binary path without a shell.
- Never put values in arguments, environment variables, temp files, or inherited
  stdout.
- Keep the Prompt Adapter's protocol pipe private to the Broker.
- Reserve stderr for scrubbed diagnostics; never log message bodies.
- Terminate the Prompt Adapter on timeout or caller cancellation.
- Treat malformed messages, unexpected extra output, or premature exit as
  `failed`.
- Do not load Prompt Adapter binaries from the current directory or `PATH`.
- Sign platform binaries and include their expected identity in packaging and
  release checks.

## Suggested initial repository structure

The repository can be Bun-led without forcing the native project into a Bun
workspace:

```text
keykong/
├── package.json
├── bun.lock
├── src/                             # Bun CLI, validation, and delivery
├── native/
│   └── macos/                       # Swift package and AppKit helper
├── tests/
└── docs/
```

The root is one Bun package, while Swift Package Manager owns the macOS helper.
Add Bun workspaces or new native platform directories only when another
implementation actually requires them.

## Alternatives

| Model | Advantages | Costs | Recommendation |
|---|---|---|---|
| Bun Broker + sidecar Prompt Adapters | One delivery implementation, crash isolation, ordinary native toolchains | Explicit IPC and per-platform packaging | **Use** |
| Bun + in-process FFI | Function-call ergonomics, no serialization | Experimental Bun FFI, ABI/lifecycle coupling, native crash takes down Broker | Avoid initially |
| Each Prompt Adapter owns prompting and delivery | Bun never sees submitted values | Duplicated sink and policy logic; inconsistent behavior likely | Use only if threat model requires Broker isolation |
| WebView for all desktop UI | Maximum UI reuse | Not an OS-native dialog; expands web-renderer attack surface | Viable product alternative, not equivalent UX |
| Hosted webpage as local Prompt Adapter | No desktop UI packaging | Cannot directly reach local sinks; changes trust boundary | Treat as separate product mode |

## Settled scope

Bun is trusted with submitted values, the Swift helper is bundled and one-shot,
and macOS is the only required implementation. Windows and web are evidence
that the function boundary should not expose AppKit-specific concepts; their
transports and projects remain deferred.
