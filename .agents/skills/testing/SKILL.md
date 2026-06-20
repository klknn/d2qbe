---
name: testing
description: Practices for writing and running unittests and integration tests for the d2qbe compiler.
---
# Testing Guidelines for d2qbe

This skill describes how to write and run tests for the `d2qbe` compiler.

## Unittests
- Location: Native D `unittest` blocks inside `source/d2qbe/*.d`.
- Command: `make unittest`
- Why: macOS process/linker overhead makes integration tests slow. `make unittest` compiles and runs native unit tests in-memory under 1 second.
- Rule: Always write unit tests before writing code!

## Integration Tests
- Location: `test/run.sh`
- Command: `make test`
- Usage: Verifies end-to-end compiler output, compilation via `qbe`, and execution.
