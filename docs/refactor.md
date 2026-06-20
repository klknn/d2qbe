# Refactoring Plan & History

This document tracks the refactoring efforts for the `d2qbe` compiler to improve code quality, safety, and maintainability without hindering the self-hosting goal.

## Phase 1: Safety & Clean-up (Completed)

Goal: Fix duplicate code and add bounds checks to prevent silent memory corruption.

### 1.1 Remove Duplicate `get_type_size`
- **Issue**: Both `parse.d` and `codegen.d` had identical implementations of `get_type_size(Type)`.
- **Fix**: Removed the definition in `codegen.d` and reused the one from `parse.d`.

### 1.2 Global Array Bounds Checking
- **Issue**: Fixed-size global arrays were used without bounds checking, risking buffer overflows in larger programs.
- **Fix**: Added assertions before writing to:
  - `known_types` in `parse.d` (size 200)
  - `code` in `parse.d` (size 500) via a new `add_to_code` helper.
  - `string_pool` in `codegen.d` (size 500)
  - `globals` in `codegen.d` (size 200)
  - `locals` in `codegen.d` (size 200)

### 1.3 Temporary Register Tracking Safety
- **Issue**: `reg_types` (size 2000) was accessed directly with calculated indices (`r + 1`, `ret_var + 1`), risking out-of-bounds access.
- **Fix**: Introduced `set_reg_type` and `get_reg_type` helper functions in `codegen.d` that assert index safety.

---

## Phase 2: Future Refactoring Opportunities (Proposed)

These can be tackled as needed or during Stage 4.

### 2.1 Centralize Constants
- Move array size limits (200, 500, 2000) to a centralized configuration module or define them as named constants instead of magic numbers.

### 2.2 Parser Clean-up: `is_decl_statement`
- The lookahead logic in `is_decl_statement` is complex. It could be simplified or better documented.

### 2.3 Context Object (De-globalization)
- Currently, the lexer, parser, and codegen share state via globals (e.g., `token`, `user_input`, `locals`).
- *Pros*: Simple, easy to self-host.
- *Cons*: Not thread-safe, hard to reuse as library.
- *Decision*: Keep globals for now to facilitate easier self-hosting, but monitor if it becomes a bottleneck.
