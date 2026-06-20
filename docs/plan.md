# d2qbe Self-Hosting Implementation Plan

This document outlines the minimal design and implementation strategy to achieve a self-hosting `d2qbe` compiler.

---

## Core Philosophy: Minimum Design

To maximize readability and ensure we can easily self-host, we keep the design minimal:
1. **Flat Types**: Instead of nested pointer/array trees, we represent types as a flat structure:
   ```d
   struct Type {
     char* name;      // Base type name ("int", "char", "bool", "void", or custom struct/enum)
     int ptr_depth;   // Pointer indirection level (0 for T, 1 for T*, 2 for T**, etc.)
     int array_size;  // Fixed-size array size (0 if not an array, >0 if fixed-size array T[N])
   }
   ```
2. **Stack Allocation for Locals**: All local variables and parameters are allocated on the stack via QBE's `alloc4` / `alloc8` / `alloc` (for structs/arrays). QBE's backend optimizer automatically performs register promotion (mem2reg) and register allocation. This keeps the compiler frontend free of complex SSA calculation.
3. **No Const/Extern checking**: Type qualifiers like `const` and modifiers like `extern(C)` are parsed and discarded. They do not affect code generation or memory layout.

---

## Roadmap & Implementation Stages

### Stage 1: Basic Types, Pointers, and Variable Declarations
- **Lexer**: Add keywords (`struct`, `enum`, `cast`, `sizeof`, `const`, `extern`, `unittest`) and punctuation (`.`, `[`, `]`).
- **Type Registry**: Maintain a list of registered type names.
- **Parser**: Parse variable declarations (`Type var;` or `Type var = init;`).
- **Symbol Table**: Map local variables to their Types and track scope.
- **Codegen**: Generate `alloc` for all local variables.

### Stage 2: Pointer Arithmetic, Indexing, and Casts
- **Pointer Arithmetic**: Scale integers by size of pointed-to type in addition/subtraction.
- **Casts**: Parse `cast(Type) expr`. Treat as no-op or simple copy/truncation in QBE.
- **Array Indexing**: Parse `x[y]` as `NodeKind.index`. Codegen computes address `x + y * element_size` and loads/stores.

### Stage 3: Sizeof, Global Variables, and String Literals
- **Sizeof**: Compile-time constant property evaluation for `Type.sizeof`.
- **Global Variables**: Declare and emit QBE global data blocks (`data $name = { ... }`).
- **String Literals**: Collect string constants and emit them in global memory.

### Stage 4: Structs and Enums
- **Structs**: Parse `struct Name { Members... }`. Track field offsets and total size. Implement member access `expr.field` (auto-dereference if `expr` is a pointer to a struct).
- **Enums**: Parse `enum Name { Members... }`. Map members to compile-time integer constants.

### Stage 5: Unittest Block Support
- **Unittests**: Parse `unittest { ... }` blocks.
- **Codegen**: Collect all `unittest` blocks in a module and compile them into a test runner function (e.g., `__unittest_runner()`).
- **Execution**: Provide a flag (e.g., `-unittest`) to execute the unittest runner when the binary is run.

### Stage 6: Self-Hosting Trial
- Compile `d2qbe` using itself, generate QBE IR, build the self-hosted binary, and verify that the self-hosted binary can successfully compile the compiler again and pass all tests.

---

## Handover and Todo/Partial Implementations
If we encounter complex D features not needed for compiler self-hosting (e.g., advanced templates, operator overloading, nested structs), they will be documented as `TODO` and left partially implemented.

## Git Commit Rules
All work will be committed to the `agy` branch in small, logically isolated commits. Every commit must keep the build and tests green.
