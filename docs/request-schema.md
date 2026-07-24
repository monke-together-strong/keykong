# Request schema

Key Kong accepts one JSON request from a file or explicit standard input:

```sh
key-kong request request.json
producer | key-kong request -
```

A request declares `schemaVersion: 1`, has a stable request `id`, a dialog
`title`, required `fields` in presentation order, and optional `deliveries`.
Run `key-kong schema` for the machine-readable JSON Schema, `key-kong --help`
for usage, and `key-kong --version` for the installed version.

Fields may be `text`, `secret`, `select`, or `multi_select`. Deliveries append
rendered templates or insert them before an existing line in an absolute,
existing readable and writable regular file. Every secret field must be
referenced by at least one delivery.

The serialized request is limited to 1 MiB. A request may contain at most 256
fields and 256 deliveries, and each select field may contain at most 256
options.

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
standard output. Every result has a `status` and `values` object:

- `completed`: prompting and every delivery succeeded.
- `partial`: at least one delivery succeeded and at least one failed;
  `failedDeliveries` contains only the failed delivery IDs.
- `failed`: the request did not complete because of usage, validation, prompt,
  delivery, or internal failure. This includes the case where every delivery
  failed.
- `cancelled`: the user cancelled the prompt.
- `expired`: the whole-request deadline elapsed.

Failures use a structured `error` with one of these stable categories:

- `CLI_USAGE`: the command shape is invalid.
- `INVALID_REQUEST`: the request cannot be read, decoded, or validated.
- `PROMPT_FAILED`: the native helper could not start or returned an invalid
  response or submission.
- `DELIVERY_FAILED`: one or more deliveries failed.
- `INTERNAL_FAILURE`: an unexpected Broker failure occurred.

Exit code `0` is reserved for `completed`. Other valid request outcomes,
including `partial`, `failed`, `cancelled`, and `expired`, exit `1`. CLI misuse
and invalid requests exit `2`. The JSON status and error code are the canonical
machine-readable outcome; human diagnostics go to standard error.
