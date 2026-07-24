# Request schema

Key Kong accepts a JSON request from a file or standard input:

```sh
key-kong request --request request.json
producer | key-kong request --request -
```

A response-field request has a stable request `id`, a dialog `title`, and
required `fields` in presentation order.

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
    }
  ]
}
```

Field IDs and option values are stable caller-facing identifiers. Labels are
display-only and may change without changing the result contract. A completed
request returns strings for text and select fields and arrays for multi-select
fields:

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
