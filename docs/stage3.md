# Stage 3: Sizeof, Global Variables, and String Literals

This document describes the design, specifications, and test plans for Stage 3.

---

## 1. Specifications

### `.sizeof` Property
- **Syntax**: `Type.sizeof` (e.g. `int.sizeof`, `char*.sizeof`, or struct names).
- **Semantics**: Evaluates to a compile-time constant integer representing the byte size of `Type` (4 for `int`, 8 for pointers, 1 for `char` / `bool`, and custom sizes for structs).

### Global Variables
- **Syntax**: Variable declarations at the global scope (e.g. `int global_var;` or `int* global_ptr = 0;`).
- **QBE Representation**: Global variables are emitted as QBE top-level data blocks:
  - Uninitialized/zero-initialized: `data $name = { z size }`
  - Initialized to a number: `data $name = { w val }` or `data $name = { l val }` depending on type.

### String Literals
- **Syntax**: Double-quoted character sequences (e.g. `"wrong number of args\n"`).
- **QBE Representation**:
  - Collected into a global string pool during code generation.
  - Emitted at the end of the module as QBE data blocks:
    `data $str0 = { b "wrong number of args\n", b 0 }`
  - In expressions, evaluated as a 64-bit pointer copy to the symbol:
    `%t =l copy $str0`

---

## 2. Implementation Strategy

1. **Tokenizer**:
   - Parse `"..."` string literals. Define a new token kind `TokenKind.str_literal`.
2. **Parser**:
   - Parse `Type.sizeof` as a `NodeKind.num` with the pre-evaluated type size.
   - Collect top-level declarations that are not functions as global variables.
3. **Code Generator**:
   - For `NodeKind.gvar_decl`, emit QBE data blocks.
   - For `TokenKind.str_literal`, register the literal in `string_pool` and emit `%t =l copy $str[idx]`.
   - Provide a `gen_strings()` method called at the end of compiling `code` to emit the string pool data blocks.
