# Handover Document

This document is for the next AI agent or developer taking over the development of the `d2qbe` compiler.

---

## 1. Project Overview & Architecture
`d2qbe` is a minimal compiler designed to compile a `betterC` subset of the D language into QBE Intermediate Representation (IR). 

- **Frontend**: A hand-written lexer and parser in D (`tokenize.d` and `parse.d`).
- **Backend**: A D-based code generator (`codegen.d`) emitting QBE IR assembly, which is then processed by QBE (`qbe/qbe`) and compiled into native binaries using a C linker (`cc`/`clang`).
- **Self-Hosting Goal**: The primary goal is compiler self-hosting (compiling `d2qbe` using `d2qbe` itself).

---

## 2. Current State
- **Stage 1 (Types, Pointers, Stack Locals)**: Completed & Committed.
- **Stage 2 (Pointer Arithmetic, Indexing, Casts)**: Completed & Committed.
- **Stage 3 (Sizeof, Globals, String Literals)**: Completed & Committed.
- **Assertion Support**: Completed & Committed. `assert(cond);` statements are fully supported, calling standard library `exit(1)` on failure.
- **Staging Branch**: `agy` contains all build-passing and test-passing commits.

---

## 3. Test Suites
Testing can be run using the following targets:
- **Unit Tests**: `make unittest`
  - Runs in-memory module-level tests inside `source/d2qbe/*.d` in under 1 second.
- **Integration Tests**: `make test`
  - Runs end-to-end integration tests using `test/run.sh`.
  
*Note: With the addition of `assert`, we are now ready to start writing fast, native D-based test files instead of slow shell-based integration tests.*

---

## 4. Next Steps (Stage 4: Structs & Enums)
The next task is to design, plan, and implement Stage 4:
1. **Struct Declarations & Memory Layout**:
   - Parsing `struct Name { Type field; ... }`.
   - Resolving struct sizes and field offsets (needs padding/alignment logic).
   - Local and global allocation/initialization of structs.
2. **Member Access**:
   - Support for `struct_var.field` (address-offset resolution).
   - Support for pointer access `struct_ptr.field` (in D, `->` is not used; member access on pointers automatically dereferences, which should compile to `%offset =l add %ptr, offset` followed by load/store).
3. **Enums**:
   - Parsing `enum Name = value;` or `enum { ... }` as compile-time constants.

---

## 5. Instructions for the Next Agent
- **Strict TDD Order**: Always write planning documentation (e.g. `docs/stage4.md`) and tests first before modifying the source files.
- **Agent Skills**: Consult the custom skills in `.agents/skills/` (`qbe`, `d`, and `testing`) for guidelines on generating QBE IR, handling the D frontend, and executing tests.
- **Keep Design Minimal**: Prefer stack slot allocation and simple designs to facilitate easier self-hosting.
