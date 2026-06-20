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
- **Switch Statements**: Completed & Committed.
  - Supports standard integer expressions, case/default labeled entry points, fallthrough behavior, and break handling.
- **Multidimensional Static Arrays**: Completed & Committed.
  - Supports nesting of static array dimensions, indexing, compile-time property `.sizeof` for both types and expressions, and recursive copying of nested arrays inside structs.
- **Assertion Support**: Completed & Committed.
- **Classic Minic Snippet Tests**:
  - `test/collatz_test.d` (collatz conjecture), `test/prime_test.d` (prime numbers), `test/queen_test.d` (eight queens), `test/switch_test.d` (switch/case branches), and `test/multidim_test.d` (multidimensional array indexing/sizing) are fully ported and verified under self-hosting.

---

## 3. Test Suites

### 3.1 Unit Tests (`make unittest`)
- **How they work**: Runs built-in D `unittest` blocks inside compiler source files (`tokenize.d`, `parse.d`, `codegen.d`).
- **Implementation**: The Makefile compiles these files with the `-unittest -main` flags using LDC and runs the resulting `unittest_runner` binary.
- **Coverage**:
  - `tokenize.d`: Verifies identifier parsing, character literals, escape sequences, and keyword recognition.
  - `parse.d`: Verifies AST structure for complex expressions, operator precedence (e.g. shifts, bitwise, logical operators), and struct/enum type layout calculation.
  - `codegen.d`: Verifies namespace management and stack variable offset layout.

### 3.2 Integration Tests (`make test`)
- **How they work**: Runs end-to-end integration tests using `test/run.sh`.
- **Harness Details**:
  - `assert <expected_exit_code> "<d_snippet>"`: Wraps the D snippet inside `int main() { ... }`, compiles it to QBE IR using `./d2qbe`, compiles QBE IR to assembly using `./qbe/qbe`, links with standard helpers in `test/ext.d`, runs it, and asserts the exit code.
  - `assert_v2 <expected_exit_code> "<d_file_content>"`: Same flow as `assert`, but compiles complete, multi-function D files (e.g., `test/struct_test.d`, `test/enum_test.d`).

### 3.3 Self-Hosting Verification (`./test/self_host.sh`)
- **How it works**: Compiles the compiler using itself, and then runs the entire integration test suite using the self-hosted binary.
- **Verification Flow**:
  1. Concatenates all compiler source files (`tokenize.d`, `parse.d`, `codegen.d`, `app.d`) into a single file `test/self_host.d` (excluding module/import declarations).
  2. Compiles `test/self_host.d` using the bootstrap compiler `./d2qbe` to produce `test/self_host.s` (QBE IR).
  3. Uses `qbe/qbe` to assemble `test/self_host.s` to assembly.
  4. Links the assembly with `ext.o` to produce `./test/d2qbe_self_hosted`.
  5. Sets the `D2QBE` environment variable to `./test/d2qbe_self_hosted` and runs `test/run.sh` to guarantee that the self-hosted compiler produces correct executable binaries.

---

## 4. Missing Features & BetterC Compatibility Next Steps

To further increase betterC compatibility, the following are missing and should be implemented next:

1. **Templates (Generics)**:
   - D templates are instantiated at compile-time (e.g., `struct Stack(T) { ... }` or `void swap(T)(T* a, T* b)`).
   - Implementing this requires adding a template symbol table to hold uninstantiated ASTs, and cloning/substituting types at the instantiation point (e.g., `Stack!int`).
