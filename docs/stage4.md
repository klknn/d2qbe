# Stage 4 Plan: Structs & Enums

This document outlines the plan for implementing Stage 4: Structs and Enums in the `d2qbe` compiler.

## 1. Goals

### 1.1 Structs
- Parse struct declarations: `struct Name { Type field; ... }`
- Compute memory layout: size, alignment, and member offsets (including padding).
- Support member access on values: `struct_var.field`
- Support member access on pointers (auto-dereference): `struct_ptr.field`
- Support struct assignment (member-by-member copy): `s1 = s2`
- Support local struct allocations on the stack.

### 1.2 Enums
- Parse manifest constants: `enum Name = value;`
- Parse anonymous enums: `enum { member1 = value1, ... }`
- Parse named enums: `enum Name { member1 = value1, ... }`
- Resolve enum members as compile-time constants (replaced with numbers during parsing).

## 2. Proposed Changes

### 2.1 Type System & AST (`parse.d`)
- Add `NodeKind.dot` for member access.
- Define `Member` and `StructType` structures.
- Add `registered_structs` registry.
- Add `Constant` structure and `constants` registry for enums.
- Update `Type` structure usage to support struct types.
- Update `get_type_size` and add `get_type_alignment` in `parse.d`.

### 2.2 Parser (`parse.d`)
- Implement full `parse_struct()` to populate struct registry.
- Implement `parse_enum()` to populate constant registry.
- Update `primary()` postfix parsing to handle `.` operator and create `NodeKind.dot` nodes.
- Update `primary()` identifier parsing to check `constants` registry and return `NodeKind.num` directly if found.
- Update `is_decl_statement` to support struct types (which are registered in `known_types`).

### 2.3 Code Generator (`codegen.d`)
- Refactor address generation into `int gen_addr(Node* node, int ret_var)` to support `lvar`, `deref`, `index`, and `dot`.
- Refactor load/store into `emit_load` and `emit_store` to handle different types (sizes 1, 4, 8) correctly.
- Update `NodeKind.assign` to use `gen_addr` and `emit_store`, and handle struct-to-struct copying (member-by-member).
- Update `NodeKind.dot` codegen using `gen_addr` and `emit_load`.
- Update `NodeKind.index` and `NodeKind.deref` to use the unified `gen_addr` and `emit_load` helpers.
- Update stack allocation in `NodeKind.defun` to use correct size and alignment for structs.

## 3. Implementation Steps & TDD Order

### Step 3.1: Unit Tests for Parsing & Layout
Write unit tests in `parse.d` for:
- Struct parsing and offset calculation (with padding).
- Enum parsing and constant resolution.
- Member access parsing (`x.y`, `x.y.z`).

### Step 3.2: Implement Parser Changes
- Implement `parse_struct`, `parse_enum`, and `lookup_constant` in `parse.d`.
- Modify `primary()` and `stmt()` as planned.
- Verify unit tests pass.

### Step 3.3: Unit Tests for Codegen
Write unit tests in `codegen.d` (or integration tests) for:
- Struct local allocation and member access.
- Auto-dereferencing pointer member access.
- Struct copy.
- Enums.

### Step 3.4: Implement Codegen Changes
- Implement `gen_addr`, `emit_load`, `emit_store`, and `copy_struct_members` in `codegen.d`.
- Refactor `assign`, `index`, `deref`, and `lvar` cases.
- Update stack allocation logic.
- Verify all tests pass.
