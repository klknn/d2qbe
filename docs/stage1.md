# Stage 1: Basic Types, Pointers, and Variable Declarations

This document describes the design and test specifications for Stage 1.

---

## 1. Specifications

### Lexer Additions
- **Keywords**: `struct`, `enum`, `cast`, `sizeof`, `const`, `extern`, `unittest`
- **Punctuators**: `.`, `[`, `]`

### Type Syntax (Subset of D)
A Type is defined as:
```
Type := BaseType ('*')* ('[' Number ']')?
BaseType := 'int' | 'char' | 'bool' | 'void' | StructOrEnumName
```
Modifiers/qualifiers like `const` and `extern (C)` are parsed but ignored in semantic analysis and codegen.

### Declarations
1. **Variable Declarations**:
   - `Type identifier;` (allocates on stack, default-initializes to 0)
   - `Type identifier = expression;` (allocates on stack and stores the initialized value)
2. **Function Definition**:
   - `Type identifier(ParameterList) BlockStatement`
   - `ParameterList := (Type identifier, ...)?`
3. **Function Declaration**:
   - `Type identifier(ParameterList);` (optional/external function declaration)

---

## 2. AST Design & Symbol Table

1. **AST Node Extensions**:
   - `NodeKind.var_decl`: Represents a variable declaration. Has `Type type` and variable name identifier.
   - `NodeKind.func_decl`: Represents a function definition or declaration. Has `Type return_type`, params, and body block.
2. **Symbol Table**:
   - A list/registry of local variables in the current function scope.
   - A list/registry of global variables.
   - A list of known type names to distinguish declarations from statements.

---

## 3. QBE Codegen Strategy

1. **Stack Allocation**:
   - Every local variable `x` of type `T` is allocated at the entry of the function:
     - If `T` has size 4 (e.g. `int`): `%x_addr =l alloc4 4`
     - If `T` has size 8 (e.g. pointers, `long`): `%x_addr =l alloc8 8`
     - If `T` is an array or struct: `%x_addr =l allocN size` (QBE's alignment is specified)
2. **Parameter Passing**:
   - Parameters are passed via registers (e.g. `w %param_name`).
   - On entry, we allocate them on stack: `%param_name_addr =l alloc4/alloc8` and store the parameter register there: `storew %param_name, %param_name_addr`.
3. **Variable Access**:
   - Reading `x` loads from `%x_addr` using `loadw` (for 32-bit) or `loadl` (for 64-bit).
   - Writing to `x` stores to `%x_addr` using `storew` or `storel`.

---

## 4. Unittest Strategy

To avoid the slow macOS linker/sub-process execution overhead, we use D's native `unittest` mechanism. Unittests run directly in memory using native assertions:
1. **Target**: `make unittest` will compile all modules with `-unittest -main -run` and execute the unit tests instantly.
2. **Parser Tests**: Tokenize small D snippets and verify that the AST nodes (e.g. `NodeKind.var_decl`, `NodeKind.defun` with return types) match expectations.
3. **Symbol Table Tests**: Verify local variable collection and type resolution.
