# Handover Document

This document is for the next AI agent or developer taking over the development of the `d2qbe` compiler.

---

## 1. Project Overview & Architecture
`d2qbe` is a minimal compiler designed to compile a `betterC` subset of the D language into QBE Intermediate Representation (IR). 

- **Frontend**: A hand-written lexer and parser in D (`tokenize.d` and `parse.d`).
- **Backend**: A D-based code generator (`codegen.d`) emitting QBE IR assembly, which is then processed by QBE (`qbe/qbe`) and compiled into native binaries using a C linker (`cc`/`clang`).
- **Self-Hosting**: The compiler is fully self-hosting (compiles itself, and the self-hosted compiler passes all integration tests).

---

## 2. Current State

- **Stage 1 (Types, Pointers, Stack Locals)**: Completed & Committed.
- **Stage 2 (Pointer Arithmetic, Indexing, Casts)**: Completed & Committed.
- **Stage 3 (Sizeof, Globals, String Literals)**: Completed & Committed.
- **Stage 4 (Structs & Enums)**: Completed & Committed.
  - Supports struct memory layout, pointer offsets, nested structs, and recursive copying of struct array fields (fixed in self-hosting).
- **Modulo & Bitwise Operators**: Completed & Committed.
  - Full support for `%`, `&`, `|`, `^`, `~`, `<<`, `>>`.
  - Proper expression precedence parsing (e.g., equality binding tighter than bitwise AND).
- **Assertion Support**: Completed & Committed.
- **Classic Minic Snippet Tests**:
  - `test/collatz_test.d` (collatz conjecture) and `test/prime_test.d` (prime numbers generation) are fully ported and verified under self-hosting.

---

## 3. Test Suites
Testing can be run using the following targets:
- **Unit Tests**: `make unittest`
  - Runs in-memory module-level tests inside `source/d2qbe/*.d` in under 1 second.
- **Integration Tests**: `make test`
  - Runs end-to-end integration tests using `test/run.sh`.
- **Self-Hosting Verification**: `./test/self_host.sh`
  - Verifies the self-hosted compiler compiles the entire compiler source and runs integration tests successfully.

---

## 4. Missing Features & BetterC Compatibility Next Steps

To further increase betterC compatibility and complete all minic-level tests, the following are missing and should be implemented next:

1. **Port/Run Queen (Eight Queens) Test Case**:
   - Port `qbe/minic/test/queen.c` to `test/queen_test.d` using multidimensional pointer indexing (`t[x][y]`) and recursion.
   - Verify it compiles and executes correctly.

2. **Switch Statements**:
   - Currently, `switch` is not supported.
   - Plan & implement parsing for `switch (expr) { case val: ... default: ... }` and generating corresponding QBE conditional jumps/branches.

3. **Multidimensional Static Arrays**:
   - Currently, the parser only supports single-dimensional static arrays (e.g., `int[10] arr;`).
   - Need to support multi-dimensional static array type declarations (e.g., `int[3][2] arr;`).
