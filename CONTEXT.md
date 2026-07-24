# Key Kong glossary

## Request

A blocking request for one or more user-supplied values.

## Field

A required value collected as part of a request under a stable field ID.
Response fields may be text, single-select, or multi-select and are returned to
the caller. Secret fields are delivered but never returned.

## Input adapter

A user interface that presents a request and returns submitted field values to
the request lifecycle. The default v1 adapter is a native macOS dialog.

## Option

A select choice with a display-only label and a stable returned value.

## Sink

A declared local destination that receives a request's submitted values.

## Delivery

The all-or-nothing handoff of a submitted request to its sink.
