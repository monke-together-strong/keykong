# Key Kong CLI request interface

## Recommendation

Use one structured JSON request document, selected with an explicit file-valued
option. Support `-` as the documented value for standard input.

```sh
key-kong request --request request.json
producer | key-kong request --request -
```

`--request` is required in v1. This avoids an ambiguous or accidentally-blocking
invocation when a person runs the command without a pipe or a request file.

The request document carries the full, nested request shape: fields, delivery
locations, operations, and templates. It must never contain entered values.

Use ordinary options only for small invocation controls that are not already in
the request schema, such as `--help` and `--version`. Do not represent fields,
deliveries, templates, or secrets as repeated command-line flags.

The command writes one JSON result to standard output. The result includes a
status (`completed`, `partial`, `failed`, `cancelled`, or `expired`) and any
non-secret response values keyed by stable field ID. Diagnostics belong on
standard error. Only `completed` exits successfully.

## Why this interface

- The request is structured and repeatable. A JSON document is clear to inspect,
  validate, save, and replay; a collection of flags would be shell-quoting-heavy
  and awkward for multiple fields and deliveries.
- A named request file is convenient for manual use. `--request -` keeps the
  same schema usable by skills and scripts without a temporary file.
- `-` for standard input is an established convention when it is explicitly
  documented. An explicit option also makes the graphical command's input source
  unambiguous.

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

## Rejected alternatives

- **Many CLI flags:** poor fit for nested, repeated field and delivery definitions;
  risks fragile shell quoting.
- **Standard input only:** good for automated callers but inconvenient for manual
  invocation and easy to leave waiting for input.
- **Request-file only:** straightforward but forces skills and scripts to create
  temporary non-secret files unnecessarily.
