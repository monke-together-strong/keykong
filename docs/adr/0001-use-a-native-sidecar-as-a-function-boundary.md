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
public executable at `bin/key-kong` and the private signed helper at
`libexec/key-kong-prompt`; the Broker resolves the helper from the installation,
not `PATH`. Swift contains no public CLI, request lifecycle, authoritative
validation, or delivery implementation. Bun owns authoritative request and
submission validation; Swift retains only immediate required-field feedback as
part of the native form experience.

This architecture has no application bundle, daemon, FFI, plugin registry, or
runtime adapter discovery. The security boundary protects submitted values
from accidental disclosure through process channels. A compromised Broker or
operating system, administrator access, and malicious software already capable
of inspecting the user's processes or input are outside the threat model.
