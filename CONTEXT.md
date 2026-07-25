# Key Kong

Key Kong brokers blocking requests for user-supplied values while keeping those
values out of the invoking caller's context.

## Language

**Request**:
A blocking request for one or more user-supplied values and their proposed delivery to a sink.

**Field**:
A required value collected as part of a request under a stable field ID.
Response fields may be text, single-select, or multi-select and are returned to
the caller. Secret fields are delivered but never returned.

**Option**:
A select choice with a display-only label and a stable returned value.

**Broker**:
The trusted component that owns submitted values from collection through delivery and reveals only the outcome and non-secret response values to the caller.
_Avoid_: Core, coordinator

**Prompt Adapter**:
A presentation component that collects a request's fields and returns submitted
values to the broker. It may receive delivery metadata for display, but never
resolves or writes to sinks.
_Avoid_: Input adapter, provider, broker, native adapter

**Delivery Specification**:
A request's description of its intended sink and the permitted operation that will deliver submitted values there.
_Avoid_: Sink configuration, delivery template

**Sink**:
A request-scoped local destination that receives submitted values after broker validation and user submission.
_Avoid_: Persistent sink, registered sink

**Submission**:
The user's authorization to return the collected field values to the broker for delivery to the resolved sink.
_Avoid_: Confirmation, approval

**Delivery**:
An ordered attempt to render and write submitted field values to one sink. A request is partial when some deliveries succeed and others fail.
