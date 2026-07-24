# Request schema

Key Kong accepts a JSON request from a file or standard input:

```sh
key-kong request --request request.json
producer | key-kong request --request -
```

A request has a stable request `id`, a dialog `title`, required `fields` in
presentation order, and optional `deliveries` in execution order.

```json
{
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
      "id": "write-token",
      "path": "/absolute/path/to/existing.env",
      "operation": "insert_line",
      "line": 2,
      "template": "API_TOKEN={{ api_token }}"
    },
    {
      "id": "write-release",
      "path": "/absolute/path/to/existing.log",
      "operation": "append",
      "template": "{{ release_name }}\\n"
    }
  ]
}
```

Field IDs and option values are stable caller-facing identifiers. Labels are
display-only and may change without changing the result contract. Secret fields
are masked by default in the dialog and may be temporarily revealed. A completed
request returns strings for text and select fields and arrays for multi-select
fields. Secret fields are omitted:

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

## Outcomes

Every invocation writes exactly one JSON result to standard output. Only
`completed` exits with code zero; `partial`, `failed`, `cancelled`, and
`expired` exit nonzero. Human-readable diagnostics, when present, are written
only to standard error.

A request is `partial` when at least one delivery succeeds and at least one
fails. Completed deliveries remain applied, non-secret submitted values are
returned, and `failedDeliveries` contains only the failed delivery IDs:

```json
{
  "status": "partial",
  "values": {
    "release_name": "2026.07"
  },
  "failedDeliveries": ["write-token"]
}
```

When all deliveries fail, the status is `failed` and `failedDeliveries` is
omitted. Validation and worker failures also return `failed`. Cancellation and
the ten-minute whole-request timeout return `cancelled` and `expired`,
respectively, with empty `values`. The timeout starts before Key Kong reads the
request and also bounds the dialog and delivery worker.

Delivery IDs are stable. Every target must be an existing readable and writable
regular file at an absolute path. An `insert_line` delivery inserts the rendered
template before its one-based `line`; Key Kong adds a trailing newline when the
rendered template does not already have one. An `append` delivery writes the
rendered template exactly at the end of the file and must not declare `line`.
Deliveries run in request order, including deliveries that share a target.
Delivery writes run in a child process, which inherits the CLI caller's
operating-system sandbox and permissions.

Templates perform only `{{ field_id }}` substitution. Template field references
must exist, and secret fields must be referenced by at least one delivery.
Text and single-select fields render as their submitted value. Multi-select
fields render as a compact JSON array of option values, preserving request
order, such as `["api","web"]`. Key Kong validates fields, templates, delivery
IDs, paths, and insertion lines before opening the dialog.
