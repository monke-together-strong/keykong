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

Fields may be `text`, `secret`, `select`, or `multi_select`. Template
deliveries append rendered content or insert it before an existing line.
`set_env` deliveries set one dotenv key from one `text`, `secret`, or `select`
Field. Every Sink is an absolute, existing readable and writable regular file,
and every secret Field must be referenced by at least one Delivery.

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
      "id": "release_log",
      "path": "/absolute/path/to/existing.log",
      "operation": "append",
      "template": "Release {{ release_name }} targets {{ environment }}\n"
    },
    {
      "id": "environment_token",
      "path": "/absolute/path/to/existing.env",
      "operation": "set_env",
      "key": "API_TOKEN",
      "field": "api_token"
    }
  ]
}
```

`append` requires `template` and forbids `line`. `insert_line` requires both
`template` and a positive, one-based `line`. `set_env` requires `key` and
`field`, and forbids `template`, `line`, and dialect selectors. Environment
keys match `^[A-Za-z_][A-Za-z0-9_]*$`; source Fields must be single-valued.
Repeated `(path, key)` pairs in one Request are invalid.

`set_env` matches the exact, case-sensitive active key while ignoring comments
and accepting indentation, whitespace around `=`, and an optional `export`
prefix. It appends a missing Environment Assignment or replaces the complete
right-hand side of one existing assignment while preserving its prefix through
`=`. Duplicate active keys, invalid UTF-8, mixed LF/CRLF endings, and multiline
quoted assignments fail without Delivery mutation.

Submitted values are serialized only when Node's dotenv parser reconstructs the
exact string. Key Kong tries double-quoted, single-quoted, then unquoted forms.
It preserves the Sink's LF or CRLF style and never creates a missing target.

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
