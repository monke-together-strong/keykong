# Key Kong CLI request interface

## Recommendation

Use one structured JSON request document as the required file operand. Support
`-` as the documented value for standard input.

```sh
key-kong request request.json
producer | key-kong request -
```

The operand is required. Invoking `key-kong request` without one returns a usage
error instead of implicitly reading standard input and potentially blocking.
The `request` subcommand already names the operation, so a second `--request`
option adds no information.

The request document carries the full prompt and delivery specification,
including fields, the proposed sink, operations, and templates. Bun validates
that specification against its built-in delivery policy before presenting the
resolved sink to the user. It declares `schemaVersion` so incompatible request
shapes fail explicitly. The document must never contain entered values.

Use ordinary options only for small invocation controls that are not already in
the request schema. Do not represent fields, deliveries, templates, or secrets
as repeated command-line flags.

The `request` command writes exactly one newline-terminated JSON result to
standard output and no other content. The result includes a status
(`completed`, `partial`, `failed`, `cancelled`, or `expired`), any non-secret
response values keyed by stable field ID, and a stable machine-readable error
code when applicable. Diagnostics belong on standard error and must never
contain submitted values.

Exit code `0` means `completed`, `1` means another request outcome, and `2`
means CLI misuse or an invalid request. Agents branch on the JSON status and
error code rather than parsing diagnostics.

The CLI also exposes:

```sh
key-kong schema
key-kong --help
key-kong --version
```

`schema` writes the request JSON Schema to standard output so agents can
discover and validate the contract programmatically.

## Why this interface

- The request is structured and repeatable. A JSON document is clear to inspect,
  validate, save, and replay; a collection of flags would be shell-quoting-heavy
  and awkward for multiple fields and deliveries.
- A named request file is convenient for manual use. `request -` keeps the same
  schema usable by skills and scripts without a temporary file.
- `-` for standard input is an established convention when it is explicitly
  documented. Requiring an explicit operand also makes the graphical command's
  input source unambiguous.
- A JSON Schema makes the nested request contract available to agents without
  requiring them to infer it from help prose.

## Source-backed conventions

- [POSIX Utility Syntax Guidelines](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
  recommend option/operand conventions for new utilities and specify `-` as the
  convention for standard input or output when a file argument is documented to
  support it.
- [POSIX utility description defaults](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap01.html)
  describe standard input handling and require diagnostics for invalid invocations
  on standard error with a nonzero exit status.
- [GNU Coding Standards: command-line interfaces](https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces)
  advise using ordinary arguments for input files, options for command controls,
  and supporting `--help` and `--version`.
- [JSON Schema](https://json-schema.org/specification) defines a
  language-neutral contract for JSON structure and validation.

## Rejected alternatives

- **Many CLI flags:** poor fit for nested, repeated field and delivery
  definitions; risks fragile shell quoting.
- **Standard input only:** good for automated callers but inconvenient for manual
  invocation and easy to leave waiting for input.
- **Request-file only:** straightforward but forces skills and scripts to create
  temporary non-secret files unnecessarily.
- **`request --request <file|->`:** explicit but redundant; the required operand
  is equally unambiguous and follows ordinary input-file conventions.
- **Multiple state-building commands:** require session state, cleanup,
  concurrency control, and recovery from partially constructed requests.
