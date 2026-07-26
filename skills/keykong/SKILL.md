---
name: keykong
description: Secret boundary for user input. Use when a workflow must collect any secret, or deliver user-supplied values into an existing local file through Key Kong.
---

# Key Kong

Key Kong brokers a blocking Request while keeping submitted secrets inside its
Prompt Adapter and Broker boundary.

## 1. Choose the boundary

- If any Field is secret, route the whole Request through Key Kong so its
  related Fields and Deliveries remain one operation. Passwords, tokens, API
  keys, and private keys are secrets.
- With only non-secret Fields, use Key Kong when its validated `append`,
  `insert_line`, or `set_env` Delivery adds value; otherwise collect the values
  directly.
- If a secret-bearing Request cannot reach `keykong`, stop before collection
  and report that Key Kong must be installed or built.

This step is complete when every requested value has one collection route.

## 2. Build the Request

Use stable IDs and ordered, required Fields:

```json
{
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

Field types are `text`, `secret`, `select`, and `multi_select`. Select Fields
add ordered `{ "label", "value" }` options. Every secret Field must be
referenced by at least one Delivery.

Deliveries target existing, readable and writable regular files at absolute
paths:

- `append`: requires `template`.
- `insert_line`: requires `template` and positive one-based `line`.
- `set_env`: requires `key` and one single-valued `field`.

Templates must contain at least one `{{ field-id }}` reference.

Before using fields or constraints not shown above, inspect the authoritative
contract with `keykong schema`.

This step is complete when every secret Field has a Delivery, every Delivery
matches its operation contract, and every target is an existing readable and
writable regular file at an absolute path.

## 3. Invoke and handle the result

Pass the JSON Request by file or explicit standard input:

```sh
keykong request request.json
producer | keykong request -
```

Key Kong writes one JSON result containing `status` and non-secret `values`.
Treat `completed`, `partial`, `failed`, `cancelled`, and `expired` as distinct
authoritative outcomes.

This step is complete when the caller handles the returned status and values,
and no submitted secret appears in agent-visible input or output.
