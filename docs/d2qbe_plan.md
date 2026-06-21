# Roadmap: Supporting Full betterC D Features in d2qbe

This document outlines the phased roadmap to support the complete `betterC` subset of the D programming language in `d2qbe`, ordered by implementation complexity.

---

## Phase 1: Simple Syntactic Extensions (Difficulty: 1/5 to 2/5)
These features require minor updates to the parser and symbol resolution, with zero to minimal changes in the code generator.

### 1.1 `alias` Declarations
* **Syntax**: `alias myint = int;`
* **Implementation**: Store aliases in a global name-to-type map. When parsing types, resolve any alias identifier to its target type.

### 1.2 `static assert`
* **Syntax**: `static assert(Val == 42);`
* **Implementation**: Parse compile-time expressions, evaluate them to constants immediately, and trigger a compiler error if the value is false.

### 1.3 Type Properties (`.init`, `.alignof`)
* **Syntax**: `int.init`, `Point.alignof`
* **Implementation**: Expand the `.sizeof` parser and evaluation logic. `.init` returns the default zero pattern of the type; `.alignof` returns the byte alignment.

### 1.4 Conditional Compilation (`version` & `debug` blocks)
* **Syntax**: `version(Posix) { ... }`
* **Implementation**: Simple preprocessor-like filtering in the tokenizer/parser to skip block contents that do not match the compiled version flags.

### 1.5 Type Inference (`auto` declarations)
* **Syntax**: `auto x = 12;`
* **Implementation**: Infer the type of the initializer expression during parsing (reusing `get_expr_type` which already exists in `codegen.d`) and assign it to the declared variable.

---

## Phase 2: Moderate Structural Features (Difficulty: 3/5)
These features require transforming D syntax into basic pointer/structure operations.

### 2.1 Slices (`T[]` types & slicing syntax)
* **Syntax**: `int[] slice = arr[1 .. 3];`
* **Implementation**: Represent a slice internally as a compiler-generated struct `struct Slice { size_t length; T* ptr; }`. Rewrite slice indexing `slice[i]` to `slice.ptr[i]`, and slice operations to struct instantiation.

### 2.2 Member Functions in Structs
* **Syntax**: `s.foo()`
* **Implementation**: Parse member functions inside struct blocks. Rewrite calls to member functions `s.foo()` to a global call `foo(&s)`, passing the address of the struct instance as the implicit `this` pointer parameter.

### 2.3 `static if`
* **Syntax**: `static if (T.sizeof == 4) { ... }`
* **Implementation**: Parse the conditional compile-time expression, evaluate it, and conditionally parse only the active branch.

### 2.4 Floating Point Support (`float` and `double` types)
* **Syntax**: `float f = 1.0f;`
* **Behavior**: In D, floating-point variables (`float`, `double`) are default-initialized to `NaN` (IEEE 754 NaN) if no explicit initializer is provided (and not initialized to `void`).
* **Implementation**:
  - Add `float` and `double` to parsed types.
  - Map `float` to QBE `s` (single) and `double` to QBE `d` (double).
  - Implement NaN constant evaluation and emission (e.g. `$nan` or custom data representation for NaN floating-point values in BSS/data).
  - Implement float arithmetic (`adds`, `addd`, `subs`, etc.) and comparisons.

---

## Phase 3: Advanced Compiler Architecture (Difficulty: 4/5 to 5/5)
These features require significant restructuring of name resolution, type validation, or code generation.

### 3.1 Function Overloading
* **Syntax**: Multiple functions sharing the same name but different signatures.
* **Implementation**: Implement compiler name mangling based on function parameter signatures (e.g. `_D4fooFia` for `foo(int, char)`). Implement overload resolution to select the correct mangled name during code generation.

### 3.2 Struct Constructors (`this()`) & Destructors (`~this()`) (RAII)
* **Syntax**: Automatically cleanup resources when struct goes out of scope.
* **Implementation**: Automatically insert constructor calls during variable initialization, and destructor calls at every scope exit point (such as `return`, `break`, or block end).

### 3.3 Modules & Imports
* **Syntax**: `module my_module; import other_module;`
* **Current Limitation**: Currently, `d2qbe` only supports compiling a single D source string. The self-hosting test script (`test/self_host.sh`) concatenates all modules (`tokenize.d`, `parse.d`, `codegen.d`, `app.d`) into a single file and strips the `module` and `import` lines to bypass this limitation.
* **Implementation**:
  - Update tokenizer/parser to accept `module` and `import` keywords without failing.
  - Implement import path lookup to locate and parse dependent `.d` files dynamically.
  - Support modular symbol tables and namespace scoping to prevent symbol conflicts.

### 3.4 Compile-Time Function Execution (CTFE)
* **Syntax**: Evaluating arbitrary functions at compile-time.
* **Implementation**: Write a lightweight AST interpreter inside the compiler to execute subset D code during compilation.

---

## Phase 4: Mini Template Support (Immediate Focus)

We will support general template blocks (`template Name(T) { ... }`) and eponymous instantiations (`Name!int`) using a lightweight **token-level substitution and mangling** approach.

### 4.1 Template Declaration Parsing
* **Syntax**:
  ```d
  template MyTemplate(T) {
      struct Point {
          T x;
          T y;
      }
  }
  ```
* **Implementation**:
  - Introduce a `TemplateSymbol` table storing registered templates.
  - When parsing `template Name(Params)`, capture the start token and end token of the template body (`{ ... }`), and the parameter names (e.g. `T`). We do *not* build an AST at this stage.

### 4.2 Explicit Instantiation & Substitution
* **Syntax**: `MyTemplate!int`
* **Implementation**:
  - When the parser encounters `Name!Arg` (e.g. `MyTemplate!int`):
    1. Look up `MyTemplate` in the `TemplateSymbol` table.
    2. Deep-copy the stored token sequence of the template body.
    3. In the copied token list, replace all identifier tokens matching parameter `T` with the argument token `int`.
    4. Save the current parser `token` stream pointer.
    5. Point the parser `token` stream to the substituted token list.
    6. Recursively parse the declarations inside the block (using the standard parser functions).
    7. Restore the original parser `token` stream.

### 4.3 Eponymous Renaming & Mangling
* **Implementation**:
  - Rename the eponymous member (the member matching the template name, e.g., `struct MyTemplate` or `void MyTemplate(...)`) inside the instantiated block to a mangled name `MyTemplate_int` or `MyTemplate_char` to avoid collisions across different instantiations.
  - Resolve the instantiation expression `MyTemplate!int` directly to that mangled name.
