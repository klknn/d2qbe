---
name: qbe
description: Guidelines and specifications for generating QBE Intermediate Representation (IR) from the D compiler frontend.
---
# QBE Intermediate Representation (IR) Generation Skill

This skill explains how to generate correct QBE IR for the `d2qbe` compiler.

## QBE Types
- `w`: 32-bit word (int, bool, char)
- `l`: 64-bit long (pointers, size_t)
- `s`: single precision float
- `d`: double precision float

## Functions
QBE function format:
```qbe
export function w $func_name(l %param1, w %param2) {
@start
  %t1 =w copy %param2
  ret %t1
}
```

## Stack Allocation
Stack variables use `alloc4` for 4-byte types and `alloc8` for 8-byte types.
```qbe
%x_addr =l alloc4 4
storew 42, %x_addr
```

## Globals
Global variables are defined at the top level using `data`:
```qbe
data $g = { w 42 }
data $str = { b "hello\n", b 0 }
```
