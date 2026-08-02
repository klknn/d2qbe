# Codex worklog and handover

## 2026-08-02: backend ABI P0

### Scope

Implement the P0 issue found during review: `dqbe` silently dropped function
arguments passed on the stack after the target ABI's argument registers were
exhausted. P1 work is explicitly out of scope for this handover.

### TDD record

1. Added `test/dqbe_abi_test.sh` and the `make test-dqbe-abi` target before
   changing backend code.
2. The new ARM64 integer test called a function with nine `w` arguments and
   returned the ninth. It failed as expected: exit status `88`, expected `9`.
3. Added a floating-point overflow case (nine `s` arguments). It initially
   produced invalid assembly (`fmov x19, s16`), exposing a separate parameter
   type propagation problem in register allocation.
4. Implemented the ABI support and parameter type seeding. Both regressions
   now pass.

### Changes made

- `source/dqbe/codegen.d`
  - Reserves aligned outgoing-call stack space, including Win64 shadow space.
  - Stores overflow `w`, `l`, `s`, and `d` call arguments in ABI stack slots.
  - Loads stack-passed callee parameters using the ARM64, SysV AMD64, and Win64
    frame layouts.
  - Restores the outgoing stack allocation after both void and value-returning
    calls.
- `source/dqbe/regalloc.d`
  - Seeds each function parameter's QBE type before liveness/allocation so
    floating-point parameters use the FP register class.
- `source/dqbe/app.d`
  - Initializes register allocation after parsing target flags, so `-t` and
    `-mtriple` select the correct register pools.
- `test/dqbe_abi_test.sh`, `Makefile`
  - Adds the native backend ABI regression to `make test` on all supported
    hosts.

### Verification completed

- `make test-dqbe-abi` — pass (ARM64 integer and float overflow arguments).
- `make unittest` — pass.
- `make test` — pass, including frontend self-hosting. The existing `dqbe`
  self-host test remains skipped on this ARM64 host by its platform guard.

### Handover / remaining validation

- The new script adapts to x86-64 (7th integer argument) and ARM64 (9th), but
  this checkout only executed the ARM64 path. Validate native x86-64 and
  Windows runners when available, particularly mixed integer/floating-point
  overflow sequences and Win64 shadow-space layout.
- No P1 cleanup (debug logging, dynamic storage, input interface, or docs
  reconciliation) was started.

### Workspace note

The pre-existing dirty `qbe` submodule was left untouched.
