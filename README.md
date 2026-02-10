# d2qbe: D language to QBE language compiler

## usage

how to compile executables step-by-step.

```bash
make all
./d2qbe "main { return 0; }" > a.ssa
./qbe/qbe < a.ssa > a.s
cc a.s -o a.out
./a.out
```

## roadmap

- [ ] tiny self hosted compiler of betterC D language
  - [x] int arith
  - [x] int variables
  - [x] control statements (if-else, for, while)
  - [x] external call of functions precompiled with ldc2
  - [x] multi-int to single int function def and call
  - [ ] pointer
  - [ ] sizeof
  - [ ] array
  - [ ] global variables
  - [ ] string
  - [ ] struct
  - [ ] initializer
- [ ] full set of betterC D language https://dlang.org/spec/betterc.html#consequences

## references

- An Incremental Approach to Compiler Construction http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf
- QBE Intermediate Language https://c9x.me/compile/doc/il.html
- D programming language spec https://dlang.org/spec/spec.html
- qbe/minic https://c9x.me/git/qbe.git/tree/minic
- A small C compiler chibicc https://github.com/rui314/chibicc
  - ja book https://www.sigbus.info/compilerbook
