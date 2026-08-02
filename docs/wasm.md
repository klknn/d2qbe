# WebAssembly backend plan

## Status and scope

This document is the design record and worklog for the `wasm` branch. The
design decisions below were recorded before implementation so that the target,
runtime contract, compatibility boundary, and tests are explicit.

The first deliverable is a small, direct WebAssembly binary backend for the
QBE subset emitted by this project. It must add no required third-party build
dependency: `ldc2` continues to build the backend, and the backend writes a
`.wasm` binary itself. WABT, Wasmtime, and Node are useful optional validators
or runners, but are not build requirements.

## Target and runtime decision

### Chosen initial target: browser-compatible core Wasm, `wasm32`

The backend will produce a Core WebAssembly binary (magic `\0asm`, binary
format version 1) using the broadly deployed MVP instruction set plus
multi-value only if it becomes necessary. The initial value types are `i32`,
`f32`, and `f64`; SIMD, threads, GC, exceptions, the component model, and
memory64 are out of scope.

The initial embedder is the JavaScript WebAssembly API, with browsers as the
primary target. A tiny JavaScript runner may also run unchanged in Node when a
developer has Node installed, but Node is not required by the repository or
the compiler. Browser-first is the right minimal-dependency choice: the Core
standard deliberately does not define a process, files, stdout, or an entry
point, while the JavaScript embedding supplies a stable way to validate,
instantiate, and invoke exports.

The module contract for milestone 1 is:

- export `main` as `() -> i32`;
- export one linear memory as `memory` when memory operations are enabled;
- do not require imports for the smoke-test subset;
- the host calls `instance.exports.main()` and compares the returned `i32`.

This is intentionally **not WASI** yet. WASI would be a separate ABI/runtime
choice with imports, a C/D runtime, I/O, allocation, and exit semantics.
Existing tests use `printf`, `malloc`, `calloc`, and variadic C calls; those
programs must remain outside the first browser-core milestone. We will add a
small host import surface only after the core code generator is proven.

## Important representation boundary

The current frontend represents host pointers as QBE `l` and assumes 8-byte
pointers (for example, `int*.sizeof == 8`). In WebAssembly `wasm32`, memory
addresses are `i32`. QBE `l` can also mean a genuine 64-bit integer, so a
standalone QBE backend cannot safely infer whether every `l` is a pointer.

Therefore the milestones are deliberately staged:

1. **M1: QBE `w` subset only.** `dqbe -t wasm32` accepts functions using `w`
   values, constants, integer arithmetic, comparisons, direct calls returning
   `w`, and returns. It rejects `l`, data, load/store, imports, and unsupported control
   flow with a clear diagnostic. This establishes valid binary encoding and a
   runnable browser module without pretending that 64-bit host layout works.
2. **M2: structured control and memory.** Lower QBE CFG to structured Wasm
   (a dispatcher-loop lowering is the reliable general strategy) and add one
   linear memory. Structured control is complete. The first memory slice
   supports `w`-addressed `loadw`/`storew` and basic active data segments; it
   still rejects ambiguous `l` values until the explicit pointer representation
   lands.
3. **M3: target-aware `d2qbe -t wasm32`.** The initial layout selection is
   implemented: pointers and `size_t` are 4 bytes, slices are 8 bytes, and
   their alignment is 4 bytes. Struct layout therefore follows wasm32 sizes
   when parsed with that target. The first explicit representation is now in
   place for target-generated local addresses: `d2qbe -t wasm32` emits them as
   QBE `w`, which maps directly to Wasm `i32`. Pointer parameters,
   dereferences, and pointer storage use the same representation. Native `l`
   remains rejected; globals, slices, and general pointer expressions still
   need conversion before memory-using D programs are enabled.
4. **M4: host imports / optional WASI profile.** Specify imports and implement
   a browser host shim first. Evaluate WASI Preview 1 or a newer WASI profile
   separately; it must not silently become a required dependency.

This boundary is strict on purpose. Mapping all QBE `l` values to Wasm `i64`
would make addresses unusable by `i32` memory instructions; mapping them all
to `i32` would silently truncate real 64-bit values. Either shortcut would be
a compiler bug wearing a tiny fake moustache.

## Browser host-import profile (M4 design, before implementation)

The first host ABI is intentionally a raw Core Wasm import surface, not a
WASI compatibility layer. Every unresolved direct QBE call whose arguments
are all `w` will become a function import in module `env`, with the QBE name
minus its leading `$` as the field name. An assignment call has signature
`(i32, ...) -> i32`; a no-result QBE call has signature `(i32, ...) -> ()`.
Defined QBE functions always take precedence over imports. Repeated calls to
one unresolved name must agree on argument count and result shape, otherwise
module emission fails instead of quietly inventing an ABI.

This gives a browser host enough room for tiny compiler shims such as
`calloc`, `fread`, `fwrite`, and diagnostics without adding a linker, WASI
SDK, JavaScript runtime dependency, or a C library to the compiler build.
The backend will only encode imports; the project will not silently provide
implementations for libc names. A browser embedding must explicitly supply
every imported field under `env`, and it owns pointer validity, memory access,
and return/error conventions. That separation makes the missing runtime
contract visible rather than treating a host function as a magic spell.

The encoder must collect imports before writing sections, emit a function type
for each import before defined-function types, emit section 2 (imports) before
the defined function section, and offset all defined-function call/export
indices by the number of imports. Initial tests will lock down one imported
word-result call and one imported void call at the binary/pipeline level;
runtime behavior remains an optional browser/Node/WABT validation concern.

This profile intentionally rejects conflicting signatures for one import name.
That currently stops a whole-compiler probe at variadic `fprintf`: Core Wasm
has no variadic function type, and the compiler uses several `fprintf`
arities. The next host-ABI design must choose explicit fixed-arity diagnostic
imports or frontend lowering to a small formatting shim; simply accepting
conflicting signatures would emit an invalid module.

## Implementation status (2026-08-02)

### Completed M1 slice

- Created the local `wasm` branch from `main`.
- Added `source/dqbe/wasm.d`, a direct binary writer with no third-party
  dependencies. It emits the Wasm magic/version and type, function, export,
  and code sections.
- Added `dqbe -t wasm32` (and `-t wasm` / wasm32 triples). Binary bytes go to
  stdout; diagnostics remain on stderr.
- Implemented the documented straight-line `w` subset: `copy`, integer
  arithmetic, bitwise operations, shifts, signed comparisons, direct calls,
  locals, and `ret`.
- Extended M2 with a dispatcher-loop lowering for labelled QBE CFGs. `jmp`,
  `jnz`, fall-through edges, and returns now work across arbitrary basic
  blocks; the program-counter local is internal to the emitted Wasm function.
  Added a one-page linear memory when a module uses `loadw` or `storew`; it
  is exported as `memory`. Those operations currently accept explicit `w`
  addresses only. Active data segments support byte strings/values, 32-bit
  words, and zero fill; `$data` resolves to a `w` address. Other widths,
  data relocations, `l`, floating point, and external calls still fail with a
  diagnostic.
- Added `d2qbe -t wasm32` / `--target wasm32` layout selection. The frontend
  now uses 4-byte pointers and `size_t`, 8-byte slices, and 4-byte pointer or
  slice alignment for that target; native compilation retains its 64-bit
  layout. The integration test compiles `int*.sizeof` through both stages and
  checks the emitted Wasm `i32.const 4`.
- Added aligned lowering of target-generated `alloc4`/`alloc8` to a mutable
  Wasm bump pointer. This makes ordinary local word variables compile through
  `d2qbe -t wasm32 | dqbe -t wasm32`; the allocator currently has one page of
  memory and no growth or deallocation, so it is a foundation rather than a
  self-hosting-ready runtime.
- Extended target-generated `w` addresses to pointer parameters and ordinary
  dereferences. Pointer values are stored with `storew` and loaded with
  `loadw`; the integration test covers `int main(int* p) { return *p; }`.
- Added static active data segments for `b`, `w`, and `z` QBE data items.
  The allocator starts after the static data, and a `w copy $data` expression
  produces that segment's linear-memory offset. The integration test locks
  down a byte segment containing `42`.
- Lowered target-generated string literal addresses and indexed string bytes
  as `w` addresses. The backend maps QBE `loadub` to Wasm `i32.load8_u`; the
  integration test compiles `"x"[0]` and asserts the byte-load opcode.
- Lowered scaled pointer addition, subtraction, and pointer differences as
  `w` arithmetic for wasm32. This keeps QBE `l` out of Wasm memory addresses
  while retaining the native `l` lowering unchanged; the pipeline test covers
  `*(p + 1)` and `*(p - 1)` for an `int*` parameter.
- Lowered mutable D global addresses as `w` values as well. Their existing
  `data { z ... }` storage is emitted into linear memory, so word reads and
  writes compile through the Wasm pipeline; the integration test covers an
  assignment to and read from `int g`.
- Added internal calls with no result. `d2qbe` now emits proper no-result QBE
  functions and `call $name(...)` instructions for `void` D calls; the Wasm
  backend emits their direct Wasm call without attempting to assign a value.
  This is covered by both a backend unit test and a D pointer-mutating helper
  pipeline test.
- Added the initial browser host-import ABI from the M4 design: an unresolved
  direct `w`-only QBE call is emitted as an explicit `env.name` function
  import. Defined QBE functions still win over imports; repeated host calls
  must use one consistent arity/result signature. Defined function indices
  are shifted after the imported functions in types, calls, and exports. The
  test suite covers both an imported word-result call and an imported void
  call through the D pipeline.
- Lowered pointer-returning D calls to the wasm32 `w` address representation,
  including the frontend's temporary constructor storage. This lets an
  imported allocator-style function return a pointer that can be dereferenced
  by the Wasm pipeline. It does not yet convert all legacy `l` address paths
  used by structs and slices in the full compiler.
- Lowered local struct-member addresses (including nonzero field offsets) to
  wasm32 `w` arithmetic. The pipeline test writes and reads both fields of a
  two-word local struct; slice layout and struct-copy paths still contain
  legacy address lowering to convert.
- Lowered pointer casts and pointer returns to the wasm32 `w` address
  representation. The pipeline test passes a cast pointer to a browser host
  import. A whole-compiler probe now reaches the intentionally rejected
  variadic `fprintf` host ABI boundary.
- Added byte stores: QBE `storeb` maps to Wasm `i32.store8`, complementing
  `loadub`. The D pipeline test covers a local `char` round trip.
- Made the bump allocator grow linear memory when a new allocation exceeds
  the current page count. It uses only Core Wasm `memory.size`/`memory.grow`,
  so no host import is required; a host memory-limit failure policy remains
  future work. The integration suite emits an allocation larger than 64 KiB
  and asserts the growth instructions.
- Added test-first coverage in `source/dqbe/wasm.d` and
  `test/dqbe_wasm_test.sh`. The unit locks down the full 38-byte encoding of
  `export function w $main() { ret 42 }`, direct result and void calls, and
  both conditional and unconditional CFG edges; the integration test checks
  both handwritten-QBE and `d2qbe -> dqbe -t wasm32` pipelines.

### Verification completed

- `make unittest-backend` — pass.
- `make test-dqbe-wasm` — pass.
- `make test` — pass. The existing backend self-host test remains skipped by
  its x86-only platform guard on this ARM64 host.
- No standalone Wasm engine or validator is installed locally, so this change
  has binary-layout and pipeline verification but not runtime execution in a
  browser, Node, Wasmtime, or WABT yet.

### Test coverage baseline

LDC `--cov` measurement of the backend unit binary reports 74.0% line
coverage for `source/dqbe/wasm.d` (463/626 executable lines) after adding
browser-import tests. `test/dqbe_wasm_test.sh` has twenty pipeline
scenarios. These are
compile-and-binary checks; semantic execution coverage remains unavailable
until an independent Wasm engine is installed in CI or locally.

## Comparison with the native backends (2026-08-02)

The x86-64 and ARM64 backends are mature native code generators: they support
the QBE types used by this compiler, arbitrary basic-block control flow,
loads/stores, global data, platform calling conventions, and the existing
native test and self-hosting paths. The Wasm backend deliberately starts much
smaller: it now covers `w` control flow, word memory, and target-generated
local storage, but it is not yet suitable for compiling the compiler itself.

| Capability | x86-64 / ARM64 | Wasm now | Self-hosting implication |
| --- | --- | --- | --- |
| QBE scalar values | `w`, `l`, `s`, `d` | `w`; local/global addresses, pointer parameters, and scaled pointer arithmetic use `w` | slices and broad pointer expressions remain pending |
| Control flow | arbitrary CFG | arbitrary CFG via dispatcher loop | ready for compiler conditionals and loops |
| Memory and data | loads, stores, globals | word/byte loads and stores, bump allocation, static strings/data, mutable word globals | wider globals and data relocations remain pending |
| Calls | native ABI, including recent stack arguments | direct internal `w` calls plus explicit `env` `w` imports | a browser host must implement the runtime contract |
| Target data layout | host-native | wasm32 size/alignment plus local-address representation | expand that representation beyond locals |
| Runtime validation | native compiler/linker/test paths | binary and pipeline checks | add an optional independent Wasm runner in CI |

### Self-hosting-first order

Wasm work is now ordered by what `d2qbe` needs to compile and run itself, not
by the easiest isolated opcode to add:

1. **General control flow:** complete for labels, `jmp`, `jnz`, fall-through,
   loops, and recursion through the dispatcher lowering.
2. **Linear memory and static data:** word load/store, aligned bump
   allocation, static data, string byte indexing, and mutable word globals
   are complete. Add typed stores/loads, data relocations/wider globals,
   bounds/growth policy, and the remaining pointer representation needed for
   D values.
3. **A wasm32-aware frontend layout:** establish pointer width, `sizeof`,
   alignment, struct layout, and pointer arithmetic as target-dependent. The
   size/alignment plus local/global-address, parameter, and scaled pointer
   arithmetic representation are complete; extend it to slices and remaining
   pointer expressions without conflating them with genuine 64-bit integers.
4. **Minimal browser host ABI:** the encoder supports explicit `env` imports
   for unresolved `w` calls. Specify and implement only the imports needed by
   the self-hosted compiler (allocation and source/input/output shims); a
   host-supplied source buffer is preferable to making a filesystem ABI an
   early requirement.
5. **Self-host compiler smoke path:** compile a constrained compiler entry
   point to Wasm, instantiate it in the browser host, and compare its output
   with the native backend on small D inputs.

Floating point, broad external ABI compatibility, and optional WASI support
remain useful but are behind those prerequisites. A self-hosted compiler uses
control flow, allocation, strings, arrays, static data, and pointers far
earlier than it needs a wide catalogue of numeric operations.

## Backend design

### CLI and artifact

Extend `dqbe` with `-t wasm32`. In this mode stdout is binary WebAssembly, so
diagnostics must stay on stderr. The invocation is:

```sh
./d2qbe -t wasm32 'extern(C) int main() { return 42; }' | ./dqbe -t wasm32 > main.wasm
```

The first implementation can live in `source/dqbe/wasm.d`, reusing the
existing tokenizer and parsed `FunctionDef`/`Instruction` structures. It will
own a small byte writer: unsigned/signed LEB128, section framing, vectors,
function type interning, and the type/function/export/code sections. No WAT
writer or external WAT assembler is required.

### Value mapping in M1

| QBE | Wasm | M1 policy |
| --- | --- | --- |
| `w` | `i32` | supported |
| `s` | `f32` | deferred until integer M1 is stable |
| `d` | `f64` | deferred until integer M1 is stable |
| `l` | ambiguous | rejected |

QBE temporaries become Wasm locals. `copy`, `add`, `sub`, `mul`, signed
`div`/`rem`, bitwise operations, shifts, and integer comparisons map to their
`i32.*` opcode equivalents. Direct calls use precomputed function indices.
Only a single `i32` result is supported initially.

### Control flow

WebAssembly branches are structured; QBE labels and jumps are arbitrary CFG.
The backend represents each QBE block with a program-counter local in a Wasm
`loop`, dispatches with nested `if` checks, and translates `jmp`/`jnz` by
setting the next block index before branching back to the loop. This is less
pretty than hand-shaped `if`/`loop`, but it is general and correct before
optimisation. A future optimisation can replace the dispatch checks with a
`br_table` ladder without changing the source-level semantics.

## Test strategy

### Project tests (mandatory)

Follow TDD: add each test before its implementation.

1. Native D unit tests for binary writer and LEB128 edge cases.
2. A backend integration script that compiles hand-written QBE to `.wasm`,
   validates/runs it through an optional runner, and asserts `main`'s result.
3. A `d2qbe -> dqbe -t wasm32` smoke test for `return 0`, arithmetic, and
   direct calls once M1 supports them.
4. Expand to control flow and memory only after the prior layer passes.

The current checkout has no `node`, `wasmtime`, `wasm-validate`, `wat2wasm`,
or `wasm-interp` executable. Tests must report a clear skip when no optional
runner is present; binary-layout unit tests remain mandatory everywhere.

### Official WebAssembly suite

The official suite is in [`WebAssembly/spec`](https://github.com/WebAssembly/spec),
which contains the reference interpreter and official tests. Its
[`test/core`](https://github.com/WebAssembly/spec/tree/main/test/core) directory
contains semantic `.wast` scripts, including integer, call, control-flow,
memory, and float tests; its README documents running them with the spec
interpreter's `run.py --wasm` interface.

It is not a drop-in M1 test suite because this backend consumes QBE rather than
Wasm text and initially implements only a strict subset. Do not vendor or
pretend to pass the suite. Instead, record a pinned upstream revision when it
is first used, select tests matching completed Wasm features, and run them
against an independent Wasm runtime as a conformance gate.

### Optional tools

- [Wasmtime CLI](https://docs.wasmtime.dev/cli-options.html): preferred
  standalone execution/validation tool when installed by a developer or CI.
- [WABT](https://github.com/WebAssembly/wabt): optional `wasm-validate`,
  `wasm-interp`, and inspection tools; not a dependency of the compiler.
- Browser JavaScript API: primary compatibility check; a simple HTML/JS runner
  can validate and invoke the exported `main` without a package manager.

## References

- [WebAssembly Core Specification](https://webassembly.github.io/spec/core/):
  module structure, validation, execution, binary format, and text format.
- [Core specification overview](https://webassembly.github.io/spec/core/intro/overview.html):
  value types, structured control flow, linear memory, exports, and embedder
  responsibilities.
- [WebAssembly JavaScript API](https://webassembly.github.io/spec/js-api/):
  browser/JavaScript embedding contract.

## Immediate next task

Add an optional independent runtime check when a browser, Node, Wasmtime, or
WABT is available, without making it a compiler dependency. The next required
self-hosting work is a wasm-compatible pointer representation followed by
linear memory/data and the minimal browser host ABI. Each capability begins
with a failing test; do not add an external runtime dependency merely to make
the unit tests pass.
