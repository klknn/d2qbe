---
name: d
description: Rules and guidance for compiling betterC D language features to QBE IR.
---
# D BetterC to QBE Compilation Skill

This skill guides compilation of the `betterC` subset of the D programming language.

## Supported Features
- Primitive Types: `int` (4 bytes), `char` (1 byte), `bool` (1 byte), pointers `T*` (8 bytes).
- `.sizeof` property evaluates to type size at compile-time.
- Local variables and global variables.
- String literals (pooled globally and referenced via `$str0`).
- Control flow (`if`, `while`, `for`, blocks).
- Pointer arithmetic and indexing (`x[i]`).
- Casts (e.g. `cast(int) char_var` translated to QBE conversions).
