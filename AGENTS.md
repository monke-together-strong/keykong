This repository is a VERY EARLY WIP. Proposing sweeping changes that improve long-term maintainability is encouraged, no backwards compatibility required.

Check [./CONTEXT.md](./CONTEXT.md) for terminology questions.

## Runtime consistency

- Bun is the package manager, runtime, test runner, and executable builder.
- Prefer direct Bun APIs in production and Bun-run scripts when they preserve the existing behavior contract.
- Retain `node:fs` and `node:path` for synchronous metadata, permissions, atomic filesystem operations, and path manipulation.
