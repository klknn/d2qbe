---
name: wasm-backend
description: Develop, test, debug, document, or review d2qbe's browser-compatible wasm32 backend. Use for changes to `dqbe -t wasm32`, `d2qbe -t wasm32`, browser Wasm fixtures or demos, host imports, Wasm test coverage, and self-hosting progress.
---

# Wasm backend

Keep the target browser-compatible Core Wasm with no required external
runtime, linker, WASI SDK, or package manager. Read `docs/wasm.md` before
changing scope or the host ABI; update it when behavior, coverage, workflow,
or the self-hosting boundary changes.

## Test-first workflow

1. Add the smallest failing case before implementation.
   - Use `test/dqbe_wasm_test.sh` for D-to-QBE-to-Wasm pipeline behavior.
   - Use a hand-written QBE case there for a backend-only feature.
   - Add a D `unittest` in `source/dqbe/wasm.d` for binary-writer branches.
2. Confirm the expected failure with `make test-dqbe-wasm` or the appropriate
   unit-test target.
3. Make the narrowest change in `source/dqbe/wasm.d` or target-aware frontend
   code in `source/d2qbe/codegen.d`.
4. Run `make unittest-frontend`, `make unittest-backend`, and
   `make test-dqbe-wasm`; run `make test` before a checkpoint commit.
5. Keep commits to one coherent feature and report measured coverage without
   claiming browser runtime semantics from byte-only tests.

## Representation and ABI rules

- Map target-generated addresses to QBE `w` / Wasm `i32` on wasm32.
- Do not reinterpret generic QBE `l` as an address: it may be a real i64.
  Reject it until frontend lowering establishes an unambiguous `w` address.
- Unresolved direct `w` calls become fixed-signature `env.<name>` imports.
  Defined QBE functions take precedence. Repeated imports must agree on arity
  and result shape.
- Do not accept variadic imports. Core Wasm has no variadic function type;
  design a fixed-arity host shim or frontend lowering first.

## Debugging order

Classify the failure before editing:

| Symptom | Inspect | Owner |
| --- | --- | --- |
| Generated QBE contains `=l`, `loadl`, or `storel` | `./d2qbe -t wasm32 <input> > program.qbe`; then `rg -n '=l|loadl|storel|call' program.qbe` | frontend/layout |
| A `w`-only QBE program fails | Feed it directly to `./dqbe -t wasm32` | backend |
| Browser instantiation fails | Check export names, `env` imports, and binary section bytes | module/host ABI |

Check the Wasm header with:

```sh
od -An -tx1 -N8 module.wasm | tr -d '[:space:]'
# 0061736d01000000
```

Use `make wasm-browser-test` for browser execution of generated fixtures and
`make wasm-browser-demo` for the interactive demo. These targets must remain
dependency-light and browser-visible; use an optional independent validator
only as an extra check.

## Self-hosting probe

Use this only as a progress probe, not as a passing test until its required
runtime ABI is complete:

```sh
./d2qbe -t wasm32 source/d2qbe/app.d | ./dqbe -t wasm32 > app.wasm
```

The current expected boundary is variadic `fprintf`. Record any new first
failure in `docs/wasm.md` with the required next design step.
