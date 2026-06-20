# Design: Switch Statement Support in d2qbe

This document outlines the design and implementation plan for adding basic `switch` statement support to the `d2qbe` compiler.

## 1. Goal
Support the standard C-style/betterC `switch` syntax for integer expressions:
```d
switch (expr) {
    case val1:
        stmt1;
        break;
    case val2:
        stmt2;
        break;
    default:
        stmt3;
        break;
}
```

## 2. Syntax & Parsing (`parse.d`)

### 2.1 Tokens
- Keywords `switch`, `case`, `default` should be added to `is_keyword` in `tokenize.d`.

### 2.2 AST Node Structure
Add NodeKind:
- `NK_switch_`: Represents the entire switch block.
  - `lhs` holds the condition expression.
  - `rhs` holds the block statement body containing `case` and `default` statements.
- `NK_case_`: Represents a case label.
  - `val` holds the case constant value.
- `NK_default_`: Represents the default label.

### 2.3 Parsing (`stmt()`)
1. When keyword `switch` is consumed:
   - Expect `(` and parse the condition expression.
   - Expect `)` and parse the statement block.
2. Inside statement parsing (`stmt()`):
   - Support parsing `case CONST:` and `default:`.
   - These act as labeled entry points similar to labels.

## 3. Code Generation (`codegen.d`)

### 3.1 Basic Translation Strategy
A switch statement can be translated into a series of conditional branches (or a jump table for dense cases). For a minimal compiler, a series of conditional jumps is robust and easy to implement.

For example:
```d
switch (x) {
    case 1: return 10;
    case 2: return 20;
    default: return 30;
}
```
Can compile to QBE:
```qbe
  # Evaluate condition
  %cond =w ...
  
  # Branch checks
  %c1 =w ceqw %cond, 1
  jnz %c1, @case_1, @next_check1
@next_check1
  %c2 =w ceqw %cond, 2
  jnz %c2, @case_2, @default
  
@case_1
  # Body for case 1
  ret 10
  
@case_2
  # Body for case 2
  ret 20
  
@default
  # Body for default
  ret 30
  
@switch_end
```

### 3.2 Loop & Break Context
Since `break` statements inside a `switch` should jump to the end of the switch, the `switch` statement needs to register itself as a breakable scope (similar to `while` and `for` loops).
- `current_loop_type` / `current_loop_id` can be generalized to `breakable_type` / `breakable_id` to route `break` statements to `@switch_end` or the enclosing loop's end correctly.
