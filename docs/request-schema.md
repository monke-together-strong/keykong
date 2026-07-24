# Request schema

Key Kong accepts one JSON request from a file or explicit standard input:

```sh
key-kong request request.json
producer | key-kong request -
```

A request declares `schemaVersion: 1`, has a stable request `id`, a dialog
`title`, required `fields` in presentation order, and optional `deliveries`.
Run `key-kong schema` for the machine-readable JSON Schema.

Fields may be `text`, `secret`, `select`, or `multi_select`. Deliveries append
rendered templates or insert them before an existing line in an absolute,
existing readable and writable regular file. Every secret field must be
referenced by at least one delivery.

```json
{
  "schemaVersion": 1,
  "id": "release-input",
  "title": "Prepare release",
  "fields": [
    {
      "id": "release_name",
      "label": "Release name",
      "type": "text"
    },
    {
      "id": "environment",
      "label": "Environment",
      "type": "select",
      "options": [
        { "label": "Production", "value": "production" },
        { "label": "Staging", "value": "staging" }
      ]
    },
    {
      "id": "services",
      "label": "Services",
      "type": "multi_select",
      "options": [
        { "label": "API", "value": "api" },
        { "label": "Web", "value": "web" }
      ]
    },
    {
      "id": "api_token",
      "label": "API token",
      "type": "secret"
    }
  ],
  "deliveries": [
    {
      "id": "environment_file",
      "path": "/absolute/path/to/existing.env",
      "operation": "append",
      "template": "TOKEN={{ api_token }}\n"
    }
  ]
}
```

Field IDs and option values are stable caller-facing identifiers. Labels are
display-only and may change without changing the result contract. A completed
request returns strings for non-secret text and select fields and arrays for
multi-select fields. Secret fields are delivered but always omitted:

```json
{
  "status": "completed",
  "values": {
    "release_name": "2026.07",
    "environment": "production",
    "services": ["api", "web"]
  }
}
```

The `request` command writes exactly one newline-terminated JSON result to
standard output. `completed` exits with code zero, cancellation exits with code
one, and CLI misuse or an invalid request exits with code two. A `partial`
result includes only the failed delivery IDs while retaining successful writes;
if every delivery fails, the result is `failed`. Failures include a structured
`error` with a stable, machine-readable code.
