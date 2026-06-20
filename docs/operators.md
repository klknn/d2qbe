# Plan: Modulo & Bitwise Operators

This document outlines the plan to implement modulo and bitwise operators in the `d2qbe` compiler.

## 1. Goal
Support the following operators to improve compatibility with typical C and D code:
- Modulo (`%`)
- Bitwise AND (`&`)
- Bitwise OR (`|`)
- Bitwise XOR (`^`)
- Bitwise NOT (`~`)
- Left Shift (`<<`)
- Right Shift (`>>`)

## 2. Proposed Changes

### 2.1 Lexer (`tokenize.d`)
Add tokenization support for:
- `%`
- `&` (already supported, but ensure single `&` is not consumed as `&&` incorrectly)
- `|`
- `^`
- `~`
- `<<`
- `>>`

### 2.2 AST & Parser (`parse.d`)
1. Add `NodeKind` members:
   - NK_mod
   - NK_bitwise_and
   - NK_bitwise_or
   - NK_bitwise_xor
   - NK_bitwise_not
   - NK_lshift
   - NK_rshift
2. Update expression parsing precedence levels:
   - `unary()`: Parse `~` as unary prefix operator -> `NK_bitwise_not`.
   - `parse_mul()`: Parse `%` alongside `*` and `/` -> `NK_mod`.
   - `parse_shift()`: New precedence level between `parse_add` and `relational` to parse `<<` and `>>`.
   - `parse_bitwise_and()`: New level between `equality` and `parse_bitwise_xor`.
   - `parse_bitwise_xor()`: New level between `parse_bitwise_and` and `parse_bitwise_or`.
   - `parse_bitwise_or()`: New level between `parse_bitwise_xor` and `parse_logical_and`.
   - Update `parse_logical_and()` to call `parse_bitwise_or()`.

### 2.3 Code Generator (`codegen.d`)
Implement QBE IR emission for the new operators in `gen()`:
- `NK_mod`: Emit `rem` (signed remainder) for integer types.
- `NK_bitwise_and`: Emit `and`.
- `NK_bitwise_or`: Emit `or`.
- `NK_bitwise_xor`: Emit `xor`.
- `NK_bitwise_not`: Emit `xor` with `-1` (e.g. `%res =w xor %val, -1`).
- `NK_lshift`: Emit `shl`.
- `NK_rshift`: Emit `sar` (arithmetic shift right).

## 3. TDD Implementation Steps

### Step 3.1: Lexer & Parser Tests
Write unit tests in `parse.d` to verify correct AST parsing and precedence.

### Step 3.2: Implement Lexer & Parser Changes
- Modify `tokenize.d` to tokenize the new symbols.
- Modify `parse.d` with new precedence structure.
- Verify parser unit tests pass.

### Step 3.3: Codegen Tests & Implementation
- Add test cases for modulo, shifts, and bitwise ops to `test/run.sh`.
- Implement codegen logic in `codegen.d`.
- Run tests and verify self-hosting works.
