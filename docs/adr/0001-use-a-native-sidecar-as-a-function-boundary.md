# Use a native sidecar as a function boundary

Each Key Kong CLI invocation runs one Bun process for one request. Bun is the
Broker and treats native prompting like an ordinary function call. On macOS,
Bun launches one bundled Swift Prompt Adapter, writes one presentation-only
JSON request to its private stdin, reads one submission or cancellation JSON
response from its private stdout, and lets the helper exit. EOF frames the
exchange. Validation, deadlines, delivery, caller-facing results, and clearing
the request lifecycle remain in Bun.

The repository contains one Bun package for the Broker and one Swift package
for the macOS Prompt Adapter. The self-contained distribution places the sole
public executable at `bin/keykong` and packages the private signed helper as
`libexec/KeyKongPrompt.app`, with the stable bundle identifier
`dev.keykong.prompt`, user-facing display name `KeyKong`, and a version derived
from the root package version; the Broker launches its nested executable
directly from the installation, not through `PATH`, `open`, or runtime
discovery. The application bundle gives Launch Services the identity required
for conventional Dock, Command-Tab, and reactivation behavior without
installing a public app or changing the one-shot helper boundary. Swift contains
no public CLI, request lifecycle, authoritative validation, or delivery
implementation. Bun owns authoritative request and submission validation;
Swift retains only immediate required-field feedback as part of the native form
experience.

The one-shot boundary is per CLI invocation, not a system-wide singleton.
Concurrent invocations may each own one helper process and one prompt.
Reactivating an existing helper raises and, when needed, deminiaturizes that
helper's existing prompt; it never creates another prompt for the same request.
Package verification checks the regular activation policy without launching an
interactive prompt. Visual testing remains an explicit developer action.

This architecture has no daemon, FFI, plugin registry, or runtime adapter
discovery. The private application bundle is packaging for the one-shot Prompt
Adapter, not a separately installed or persistent application. The security
boundary protects submitted values from accidental disclosure through process
channels. A compromised Broker or operating system, administrator access, and
malicious software already capable of inspecting the user's processes or input
are outside the threat model.
