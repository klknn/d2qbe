# Stage 2: Pointer Arithmetic, Indexing, and Casts

This document describes the design, specifications, and test plans for Stage 2.

---

## 1. Specifications

### Pointer Arithmetic
- **Addition/Subtraction (`ptr + int`, `ptr - int`)**:
  - When an integer value `i` is added to or subtracted from a pointer `p` of type `T*`, the integer must be scaled by the size of `T`:
    `actual_offset = i * sizeof(T)`
  - Size of base types:
    - Pointers (any `ptr_depth > 0`): 8 bytes.
    - `int`: 4 bytes.
    - `char` / `bool` / `void`: 1 byte.
- **Pointer Difference (`ptr1 - ptr2`)**:
  - Subtracting two pointers of the same type `T*` computes the byte difference divided by `sizeof(T)`:
    `index_diff = (ptr1 - ptr2) / sizeof(T)`

### Array and Pointer Indexing (`x[y]`)
- Indexing is parsed as `NodeKind.index` (representing `x[y]`).
- It computes the address of the element: `base_address + y * sizeof(*x)`.
- Reads from the index load the value at the computed address.
- Writes (assignment LHS) store the value to the computed address.

### Casts (`cast(Type) expr`)
- Evaluates `expr` and copies/coerces the result to the target `Type`.
- Serves as a no-op or copy in QBE for pointer-to-pointer or pointer-to-int casts, and is used for pointer arithmetic scaling adjustment.

---

## 2. AST and Codegen Design

1. **AST Representation**:
   - `NodeKind.cast_`: `lhs` is the expression to cast, `type` is the target type.
   - `NodeKind.index`: `lhs` is the array/pointer expression, `rhs` is the index expression.
2. **Type Scaling in Codegen**:
   - When generating `NodeKind.add` or `NodeKind.sub`:
     - If LHS is a pointer, we scale RHS by the size of the pointed-to type.
     - If RHS is a pointer (and LHS is an integer), we scale LHS by the size of the pointed-to type.
3. **Indexing Codegen**:
   - For `x[y]`, evaluate `x` to get `base_addr` (pointer).
   - Evaluate `y` to get `index_val`.
   - Scale `index_val` by `sizeof(*x)`.
   - Add the scaled offset to `base_addr` to get `elem_addr`.
   - If loading, emit `loadw`/`loadl` from `elem_addr`.
   - If storing (assignment LHS), emit `storew`/`storel` to `elem_addr`.
