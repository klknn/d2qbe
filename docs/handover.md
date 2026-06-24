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
- **Type Inference (`auto` declarations)**: Completed & Committed.
  - Supports `auto ident = initializer;` at both top-level and statement scopes. Performs type inference (supporting variables, literals, pointers, casts, indexing, and function calls) during local/global variable collection at the beginning of code generation.
- **Templates (Generics)**: Completed & Committed.
  - Supports template block declarations `template Name(T) { ... }` and explicit eponymous instantiations `Name!Arg` (including complex parenthesized arguments like `Name!(char*)`).
  - Implements token-level deep duplication, argument substitution, and eponymous member renaming/mangling.
  - Integrates template type resolution into variable declaration checks (`is_decl_statement`) and type property expressions (e.g. `Stack!int.sizeof`).
- **Struct Member Functions**: Completed & Committed.
  - Supports parsing member functions inside struct blocks, mangling them to `_D_struct_StructName_funcName`, and adding them as global top-level functions with an implicit `this` pointer parameter.
  - Generates address resolution for implicit member variable lookups relative to `%this_addr` during code generation.
- **Slices and Slicing**: Completed & Committed.
  - Full support for `T[]` slice types (represented as a 16-byte structure `struct Slice { size_t length; T* ptr; }`).
  - Support for compile-time/runtime slice property access (`.length` at offset 0, and `.ptr` at offset 8).
  - Support for slice indexing (`slice[i]`) and slice creation expressions (`array[start .. end]` or pointer/slice slicing).
- **Ternary Operator (`cond ? then : else`)**: Completed & Committed.
  - Supports parsing and compiling ternary expressions for scalars, slices, and structs. Allocates a temporary variable on the stack to hold the result of the evaluated branch and returns its address.
- **Floating Point Support (`float`, `double`)**: Completed & Committed.
  - Supports `float` (32-bit `s` type in QBE) and `double` (64-bit `d` type in QBE) parsing, sizing, and alignment.
  - Tokenizes and parses float/double literals (e.g. `3.14f`, `0.5e-2`), preserving them as formatted QBE constants.
  - Generates code for floating-point arithmetic (`add`, `sub`, `mul`, `div`), comparisons (`ceq[sd]`, `cne[sd]`, `clt[sd]`, `cle[sd]`, `cgt[sd]`, `cge[sd]`), return values, and parameter signatures.
  - Implements type-promoting comparisons and casts between float/double and integers using QBE conversion instructions (`exts`, `truncd`, `swtof`, `sltof`, `stosi`, `dtosi`).
- **Classic Minic Snippet Tests**:
  - `test/collatz_test.d` (collatz conjecture), `test/prime_test.d` (prime numbers), `test/queen_test.d` (eight queens), `test/switch_test.d` (switch/case branches), `test/multidim_test.d` (multidimensional array indexing/sizing), `test/template_test.d` (struct and function templates), and structured slice/member function/ternary/float integration tests inside `test/arith_test.d` are fully verified under self-hosting.

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
  1. Compiles the main entry point `source/d2qbe/app.d` directly using the bootstrap compiler `./d2qbe` to produce `test/self_host.s` (QBE IR). The parser automatically resolves and parses imported files recursively.
  2. Uses `qbe/qbe` to assemble `test/self_host.s` to assembly.
  3. Links the assembly with `ext.o` to produce `./test/d2qbe_self_hosted`.
  4. Sets the `D2QBE` environment variable to `./test/d2qbe_self_hosted` and runs `test/run.sh` to guarantee that the self-hosted compiler produces correct executable binaries.

---

## 4. Missing Features & BetterC Compatibility Next Steps

While `d2qbe` compiles a very large and self-hosting subset of D `betterC`, the following standard D features are currently unsupported:
* **`foreach` / `foreach_reverse` Loops**: Only standard C-style `for` and `while` loops are supported.
* **`scope(...)` Statements**: `scope(exit)`, `scope(success)`, and `scope(failure)` constructs are not implemented.
* **Uniform Function Call Syntax (UFCS)**: True UFCS for free-standing functions is not supported.
* **Compile-Time Function Execution (CTFE)**: There is no interpreter to evaluate custom functions at compile-time.
* **Advanced Templates**: Multiple parameters, variadic parameters, constraints, and specializations are not supported (only eponymous templates with a single type parameter).
* **C++ Classes & Interfaces**: `extern(C++) class` (which is standard betterC compatible as it does not use GC) is unsupported.

For a detailed roadmap of these remaining D `betterC` features ordered by implementation complexity, refer to the [d2qbe_plan.md](file:///Users/karita/repos/d2qbe/docs/d2qbe_plan.md) document.


---

## 5. QBE IR Subset Emitted by d2qbe (For Backend Developers)

For developers building or verifying a backend QBE clone (like `dqbe`), the `d2qbe` frontend emits the following QBE IR features, types, and instructions:

### 5.1 Types
* `w` (word - 32-bit integer)
* `l` (long - 64-bit integer / pointers)
* `b` (byte - 8-bit integer, used in memory loads/stores and global data)
* `s` (single - 32-bit floating point)
* `d` (double - 64-bit floating point)

### 5.2 Storage & Memory Instructions
* `alloc4`, `alloc8`, `alloc16` (stack allocation of local variables/structs)
* `loadsb` / `loadub` (load signed/unsigned byte from address)
* `loadsw` / `loadw` (load signed word / word from address)
* `loadl` (load long/pointer from address)
* `loads` / `loadd` (load single/double float from address)
* `storeb` (store byte to address)
* `storew` (store word to address)
* `storel` (store long/pointer to address)
* `stores` / `stored` (store single/double float to address)

### 5.3 Arithmetic & Bitwise Instructions
* `add`, `sub`, `mul`, `div` (signed operations on GPR or float types)
* `rem` (signed modulo remainder on `w` or `l`)
* `and`, `or`, `xor` (bitwise operations on `w` or `l`)
* `sar` (arithmetic shift right on `w` or `l`)
* `shl` (shift left on `w` or `l`)
* `extsw` (sign-extend word to long)
* `extsb` / `extub` (sign-extend / zero-extend byte to word)
* `exts` / `truncd` (extend single to double / truncate double to single float)
* `stosi` / `dtosi` (convert single/double float to signed integer)
* `swtof` / `sltof` (convert signed word/long to float/double)
* `cast` (bitwise cast between GPR and XMM types of the same width)

### 5.4 Comparisons
* `ceqw` / `ceql` (equal integers)
* `cnew` / `cnel` (not equal integers)
* `cslew` / `cslel` (signed less-than-or-equal integers)
* `csltw` / `csltl` (signed less-than)
* `csgew` / `csgel` (signed greater-than-or-equal)
* `csgtw` / `csgtl` (signed greater-than)
* `ceqs` / `ceqd` (equal floats/doubles)
* `cnes` / `cned` (not equal floats/doubles)
* `clts` / `cltd` (less-than floats/doubles)
* `cles` / `cled` (less-than-or-equal floats/doubles)
* `cgts` / `cgtd` (greater-than floats/doubles)
* `cges` / `cged` (greater-than-or-equal floats/doubles)

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

### 6.2 Avoid Copying Large Structs by Value
* **Limitation**: The frontend code generator has a hard-coded limit of 9,999 temporary registers (`reg_counter < 9999`). Copying large structs (e.g., a 1.9MB `FunctionDef`) by value inside loops creates thousands of intermediate QBE registers, causing a compilation crash.
* **Request**: Pass large structs by pointer, or parse/write directly into global/heap memory array slots instead of performing struct copies.

### 6.3 Syntax Constraints
* **No Backticks**: Do not use backtick strings (`` ` ``); they are not supported by the bootstrap parser. Use double quotes (`"`) instead.
* **No Global Array Literals**: Global array literal initializers (e.g. `const char*[6] arr = [...]`) cannot be parsed by the bootstrap compiler. Use helper functions with `if/else` or `switch` to return the values instead.

### 6.4 Self-Hosting and Bootstrapping Float Support Constraints
* **No Native `long` Type Support**: The bootstrap compiler `d2qbe` does not support `long` type. Writing `long* bits = ...` is parsed as an expression binary multiplication (`long * bits`), leading to compilation errors (e.g., `lvalue expected`).
  * *Workaround*: Define `alias long = int;` inside the self-host header block template (`test/self_host_dqbe.sh`) so `d2qbe` parses it as `int` under self-hosting (which is safe for bitwise extraction), while allowing the production compiler to build it as a native 64-bit integer.
* **Explicit `strtod` Declaration Required**: Calling C's `strtod` to parse float literals without an explicit declaration makes the bootstrap compiler default the return type to `int` (`'w'` type in QBE), resulting in all compiled float literals generating as `0`.
  * *Workaround*: Always declare `extern (C) double strtod(const(char)*, void*);` in the self-host header block.
* **Custom Enum Types in Overload Resolution**: The bootstrap compiler's overload resolution expects custom types (such as enums like `TokenKind`) to be pointers (register type `'l'`). Passing them by value as integers (`'w'`) causes overload resolution to fail and fall back to unmangled names.
  * *Workaround*: Define function signatures (e.g. `new_token` or `consume_kind`) taking custom enum types using `int` instead of the enum type. D implicitly converts enum members to integers, so this is 100% type-safe and fully compatible.


