# dqbe: Mini QBE Compiler Backend in D (betterC)

`dqbe` is a lightweight, simplified QBE IR compiler backend written in D under `-betterC` mode. It consumes QBE IR from `stdin` and generates x86_64 AMD64 assembly to `stdout`, complying with standard System V AMD64 calling conventions.

## Architecture & Code Structure

The project resides completely within the `source/dqbe/` directory:
- `source/dqbe/tokenize.d`: Tokenizes QBE IR (temporaries `%tN`, globals `$name`, labels `@label`, identifiers, numeric constants, strings).
- `source/dqbe/parse.d`: Parses QBE IR into AST structures (`FunctionDef`, `DataDef`, `Instruction`).
- `source/dqbe/codegen.d`: Generates x86_64 assembly instructions from the AST structures.
- `source/dqbe/app.d`: CLI entry point reading from stdin and writing to stdout.

## Compilation & Code Generation Model

### Stack-based Register Mapping
To guarantee correctness, avoid clobbering bugs, and ensure simplicity, `dqbe` maps all virtual registers/temporaries `%tN` to unique 8-byte slots relative to the frame pointer `%rbp` (CPU stack frame).
- Every temporary gets a unique offset assigned in a first pass.
- Operations load arguments into temp registers (like `%rax`, `%rcx`, `%rdx`), perform the instruction, and store the result back to the stack slot.

### Memory & Array Limits
To support building and self-hosting large codebases (like the concatenated `d2qbe` compiler), static limits have been scaled:
- **Maximum instructions per function**: `5000`
- **Maximum temporaries per function**: `10000`
- **Maximum local variable allocations per function**: `5000`
- **Maximum functions per program**: `200`
- **Maximum global data definitions per program**: `2000`

### Symbol Uniqueness
Label names are made unique across the entire assembly file by prepending the function name (e.g., `.Lmain_then5` instead of `.Lthen5`), preventing symbol redefinition errors during linking.

## Building and Verification

### Building the compiler
To build `dqbe` using `ldc2` under `-betterC` mode:
```bash
ldc2 -Isource -betterC \
  source/dqbe/tokenize.d \
  source/dqbe/parse.d \
  source/dqbe/codegen.d \
  source/dqbe/app.d \
  test/ext.d \
  -of=dqbe
```

### Self-hosting Verification
Run the self-hosting test script:
```bash
./test/self_host.sh
```
This script:
1. Concatenates all compiler source files into `test/self_host.d`.
2. Compiles `self_host.d` using the bootstrap compiler `d2qbe` to produce `self_host.s`.
3. Translates QBE IR `self_host.s` to assembly `self_host_qbe.s` using the newly built `./dqbe` backend.
4. Compiles and links the assembly to produce `test/d2qbe_self_hosted`.
5. Verifies the self-hosted compiler by compiling and passing the entire integration test suite.
