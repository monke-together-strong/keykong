---
name: keykong
description: Secret boundary for user input. Use Key Kong when a workflow must collect a secret or broker user-supplied values into an existing local file.
---

# Key Kong

Key Kong is the secret boundary. If any Field is secret, route the whole Request
through Key Kong so related fields and deliveries remain one operation.

- Use it for passwords, tokens, API keys, private keys, and other values that
  must stay out of agent context.
- Use it when user-supplied values should be delivered through validated
  `append`, `insert_line`, or `set_env` operations.
- Collect purely non-secret values directly when brokered delivery adds no
  value.

## Request contract

Pass a JSON Request by file or explicit standard input:

```sh
keykong request request.json
producer | keykong request -
```

```json
{
  "schemaVersion": 1,
  "id": "configure-service",
  "title": "Configure service",
  "fields": [
    { "id": "environment", "label": "Environment", "type": "text" },
    { "id": "token", "label": "API token", "type": "secret" }
  ],
  "deliveries": [
    {
      "id": "token",
      "path": "/absolute/path/to/existing.env",
      "operation": "set_env",
      "key": "API_TOKEN",
      "field": "token"
    }
  ]
}
```

Fields are required and ordered. Types are `text`, `secret`, `select`, and
`multi_select`; select types add `{ "label", "value" }` options. Every secret
Field needs a Delivery.

Deliveries target existing, writable regular files at absolute paths:

- `append`: requires `template`.
- `insert_line`: requires `template` and positive one-based `line`.
- `set_env`: requires `key` and one single-valued `field`.

Run `keykong schema` when exact validation constraints are needed. Key Kong
writes one JSON result with `status` and non-secret `values`; statuses are
`completed`, `partial`, `failed`, `cancelled`, or `expired`. Treat the JSON
status as authoritative.

If Key Kong is unavailable, stop before collecting the secret and report that
it must be installed or built.

Completion criterion: every secret is a `secret` Field referenced by a
Delivery, no submitted secret enters agent-visible input or output, and the
caller's result handling covers Key Kong's returned status.
