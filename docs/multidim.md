# Design: Multidimensional Static Arrays in d2qbe

This document outlines the design and implementation plan for adding support for multidimensional static array type declarations and indexing in `d2qbe`.

## 1. Goal
Support D-style multidimensional static arrays:
- Declarations: `int[3][2] arr;` (an array of 2 elements, each being an array of 3 integers).
- Indexing: `arr[i][j]` with correct pointer scaling and address calculation.

## 2. Type Representation (`parse.d`)

Modify the `Type` struct to support multiple array dimensions:
```d
struct Type {
  const(char)* name;
  int ptr_depth;
  int[5] array_sizes; // Support up to 5 dimensions
  int array_dims;     // Number of dimensions (0 if not an array)
}
```

### 2.1 Parsing (`parse_type`)
Currently, `parse_type` only consumes a single `[...]` block. We will change it to loop:
```d
  while (consume("[")) {
    int size;
    Token* tok = consume_ident();
    if (tok) {
      if (!lookup_constant(tok, &size)) {
        error_at(tok.str, "unknown constant for array size");
      }
    } else {
      size = expect_number();
    }
    
    // Shift existing dimensions to the right to make the new dimension outermost
    for (int i = t.array_dims; i > 0; i--) {
      t.array_sizes[i] = t.array_sizes[i - 1];
    }
    t.array_sizes[0] = size;
    t.array_dims++;
    expect("]");
  }
```

### 2.2 Type Size Calculation (`get_type_size`)
Update `get_type_size` to multiply the base type size by all dimensions:
```d
int get_type_size(const(Type)* t) {
  int base_size = get_base_type_size(t.name);
  if (t.ptr_depth > 0) {
    return 8; // pointer size is 8
  }
  if (t.array_dims > 0) {
    int total_size = base_size;
    for (int i = 0; i < t.array_dims; i++) {
      total_size = total_size * t.array_sizes[i];
    }
    return total_size;
  }
  return base_size;
}
```

## 3. Code Generation (`codegen.d`)

### 3.1 Type Inference for Indexing (`get_expr_type`)
When indexing a multidimensional array:
- If `base.array_dims > 0`:
  - Result has `array_dims = base.array_dims - 1`.
  - Shift remaining sizes left: `res.array_sizes[i] = base.array_sizes[i + 1]`.

### 3.2 Index Address Calculation (`gen_addr`)
When compiling `NK_index` for `arr[i]`:
- If `base.array_dims > 0`:
  - Address of `base` is calculated.
  - Scale of indexing is the size of the element type.
    - If `base.array_dims > 1`, element size is the size of the sub-array:
      `scale = base_type_size * base.array_sizes[1] * base.array_sizes[2] ...`
    - If `base.array_dims == 1`, element size is just the base type size (e.g. `int.sizeof`).
