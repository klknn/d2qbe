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
- **Alias Declarations**: Completed & Committed.
  - Supports `alias AliasName = ExistingType;` at both top-level and local block/statement scope levels. Resolves and substitutes nested pointer types (e.g. `pint*` resolving to `int**` if `pint` is `int*`).
- **Static Assertions**: Completed & Committed.
  - Supports `static assert(cond);` and `static assert(cond, "message");` at both top-level and local block/statement scope levels. Evaluates constant integer/boolean expressions at compile-time.
- **Type Properties (`.init`, `.alignof`)**: Completed & Committed.
  - Supports compile-time properties `Type.init` (default type initialization value, evaluates to 0 for scalars/pointers) and `Type.alignof` (type alignment in bytes).
- **Conditional Compilation (`version` & `debug` blocks)**: Completed & Committed.
  - Supports `version(Identifier) { ... } else { ... }` and `debug { ... }` conditional blocks at both top-level and statement scopes. Performs token-level block skipping using brace nesting checks.
- **Templates (Generics)**: Completed & Committed.
  - Supports template block declarations `template Name(T) { ... }` and explicit eponymous instantiations `Name!Arg` (including complex parenthesized arguments like `Name!(char*)`).
  - Implements token-level deep duplication, argument substitution, and eponymous member renaming/mangling.
  - Integrates template type resolution into variable declaration checks (`is_decl_statement`) and type property expressions (e.g. `Stack!int.sizeof`).
- **Classic Minic Snippet Tests**:
  - `test/collatz_test.d` (collatz conjecture), `test/prime_test.d` (prime numbers), `test/queen_test.d` (eight queens), `test/switch_test.d` (switch/case branches), `test/multidim_test.d` (multidimensional array indexing/sizing), and `test/template_test.d` (struct and function templates) are fully ported and verified under self-hosting.

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

For a detailed roadmap of all remaining D `betterC` features (slices, RAII, CTFE, etc.) ordered by implementation complexity, refer to the [d2qbe_plan.md](file:///usr/local/google/home/karita/repos/d2qbe/docs/d2qbe_plan.md) document.

---

## 5. QBE IR Subset Emitted by d2qbe (For Backend Developers)

For developers building or verifying a backend QBE clone (like `dqbe`), the `d2qbe` frontend emits the following QBE IR features, types, and instructions:

### 5.1 Types
* `w` (word - 32-bit integer)
* `l` (long - 64-bit integer / pointers)
* `b` (byte - 8-bit integer, used in memory loads/stores and global data)

### 5.2 Storage & Memory Instructions
* `alloc4`, `alloc8`, `alloc16` (stack allocation of local variables/structs)
* `loadsb` / `loadub` (load signed/unsigned byte from address)
* `loadsw` / `loadw` (load signed word / word from address)
* `loadl` (load long/pointer from address)
* `storeb` (store byte to address)
* `storew` (store word to address)
* `storel` (store long/pointer to address)

### 5.3 Arithmetic & Bitwise Instructions
* `add`, `sub`, `mul`, `div` (signed operations on `w` or `l`)
* `rem` (signed modulo remainder on `w` or `l`)
* `and`, `or`, `xor` (bitwise operations on `w` or `l`)
* `sar` (arithmetic shift right on `w` or `l`)
* `shl` (shift left on `w` or `l`)
* `extsw` (sign-extend word to long)
* `extsb` / `extub` (sign-extend / zero-extend byte to word)

### 5.4 Comparisons
* `ceqw` / `ceql` (equal)
* `cnew` / `cnel` (not equal)
* `cslew` / `cslel` (signed less-than-or-equal)
* `csltw` / `csltl` (signed less-than)
* `csgew` / `csgel` (signed greater-than-or-equal)
* `csgtw` / `csgtl` (signed greater-than)

### 5.5 Control Flow & Call Instructions
* `jmp @label` (unconditional jump)
* `jnz %cond, @label_then, @label_else` (conditional jump)
* `ret` / `ret %val` (return from function)
* `call $func(...)` (call global function)

### 5.6 Declarations
* `export function [type] $name([params]) { ... }` (function definition)
* `data $name = { [items] }` (global data definition using `b`, `w`, `l`, or string literals)

---

## 6. [dqbe] requests

To ensure the backend compiler `dqbe` compiles successfully under self-hosting (when compiled by `d2qbe`), the codebase must conform to the following bootstrap compiler limitations:

### 6.1 Avoid `extern` Global Variables
* **Limitation**: The bootstrap compiler `d2qbe` does not support `extern` global variables (e.g. `extern (C) extern FILE* stderr;`). It compiles them as unallocated local stack variables, causing immediate segmentation faults when dereferenced.
* **Request**: Do not declare or use direct `extern` global variables. Instead, wrap them in `extern (C)` helper functions (e.g. `extern (C) void* get_stderr();`) and compile/link them via an external helper object like `test/tmp_ext_dqbe.d`.

### 6.2 Avoid Byte-Sized (`char` / `byte`) Function Parameters
* **Limitation**: The bootstrap compiler allocates function parameters sequentially on the stack without padding or alignment. When a byte-sized parameter (like `char`) is stored via a 4-byte QBE `storew` instruction, it overwrites the lowest 3 bytes of the adjacent variable on the stack, causing stack corruption.
* **Request**: In function signatures, use `int` instead of `char` for scalar parameters.

### 6.3 Avoid Copying Large Structs by Value
* **Limitation**: The frontend code generator has a hard-coded limit of 9,999 temporary registers (`reg_counter < 9999`). Copying large structs (e.g., a 1.9MB `FunctionDef`) by value inside loops creates thousands of intermediate QBE registers, causing a compilation crash.
* **Request**: Pass large structs by pointer, or parse/write directly into global/heap memory array slots instead of performing struct copies.

### 6.4 Syntax Constraints
* **No Backticks**: Do not use backtick strings (`` ` ``); they are not supported by the bootstrap parser. Use double quotes (`"`) instead.
* **No Self-Assignments**: Self-assignments (e.g. `+=`, `-=`, `*=`) are not supported. Use full expansions (e.g. `x = x + 1`) instead.
* **No Global Array Literals**: Global array literal initializers (e.g. `const char*[6] arr = [...]`) cannot be parsed by the bootstrap compiler. Use helper functions with `if/else` or `switch` to return the values instead.

