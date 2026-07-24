# Request schema

Key Kong accepts one JSON request from a file or explicit standard input:

```sh
key-kong request request.json
producer | key-kong request -
```

A request declares `schemaVersion: 1`, has a stable request `id`, a dialog
`title`, required `fields` in presentation order, and optional `deliveries`.
Run `key-kong schema` for the machine-readable JSON Schema.

The current Bun migration slice executes response-only requests: text,
single-select, and multi-select fields with no deliveries. Secret fields and
delivery specifications remain represented in version 1 and in the private
Prompt Adapter protocol so the boundary can expand without redesign, but the
Bun CLI rejects their execution until the secret-delivery slice.

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
    }
  ]
}
```

Field IDs and option values are stable caller-facing identifiers. Labels are
display-only and may change without changing the result contract. A completed
response request returns strings for text and select fields and arrays for
multi-select fields:

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
one, and CLI misuse or an invalid request exits with code two. Failures include
a structured `error` with a stable, machine-readable code.
