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

## Hands-on contributor workflow

This backend is developed as a small vertical slice at a time: write a
failing test, implement the smallest valid binary lowering, inspect the
emitted module, then run the complete regression suite before committing.
The backend intentionally has no mandatory external Wasm toolchain.

### Build and run the smallest module

Build the two compiler stages from the repository root:

```sh
make d2qbe dqbe
```

Compile a no-import D program to a binary module. `dqbe` writes bytes to
standard output, so redirect its output; compiler diagnostics remain on
standard error.

```sh
./d2qbe -t wasm32 'extern(C) int main() { return 42; }' \
  | ./dqbe -t wasm32 > main.wasm

od -An -tx1 -N8 main.wasm | tr -d '[:space:]'
# 0061736d01000000
```

For a browser smoke test, put `main.wasm` next to an `index.html`, serve the
directory with any static-file server, and open it in a current browser.
Opening the page with `file://` can prevent `fetch` from loading the module.

```html
<!doctype html>
<script type="module">
  const response = await fetch("./main.wasm");
  const { instance } = await WebAssembly.instantiate(
    await response.arrayBuffer(), {});
  console.log(instance.exports.main()); // 42
</script>
```

`python3 -m http.server` is a convenient server if Python is already
available, but it is not a project dependency.

### Run the browser suite and demo

`make wasm-browser-test` rebuilds and serves browser fixtures that mirror all
twenty cases in `test/dqbe_wasm_test.sh`, opens the browser test page, and
leaves the local server running until `Ctrl-C`. The page instantiates every
module, calls its exported `main`, checks the return value and required memory
page count, and supplies the fixed `env` imports used by the host-import
tests. Its pointer-arithmetic fixture verifies the deterministic expression
`(pointer + 1) - pointer`; it does not read uninitialised linear memory.

```sh
make wasm-browser-test
```

`make wasm-browser-demo` builds and opens an interactive slider demo. Its
Wasm module imports `env.host_value`; moving the slider changes the host value
and reruns compiled Wasm that calculates `n² + 1`.

```sh
make wasm-browser-demo
```

`make wasm-browser-game` keeps that demo intact and opens **Wasm Tetromino**,
a dependency-free falling-block game. Browser JavaScript owns input, drawing,
collision, rotation, and line clearing; the separately compiled `game.wasm`
owns the score formula: `lines * 100 + level * 50 + combo * 25`. This makes
function arguments and integer arithmetic observable through a small
interactive program without requiring a runtime or game framework.

```sh
make wasm-browser-game
```

### Run D-only WASM-4 cartridges

The browser demos above are useful backend probes, but WASM-4 is the preferred
route when the game itself — state, input handling, and drawing calls — should
be written entirely in D. `demo/wasm4/wasm4.d` is a deliberately small binding
for the project's betterC subset. It declares WASM-4's official `env.rect`
import and accesses `DRAW_COLORS` and `GAMEPAD1` through the console's
memory-mapped addresses. It writes the two `DRAW_COLORS` bytes separately, so
the current byte-store backend is sufficient and does not overwrite adjacent
input registers. The build uses the dedicated `wasm4` profile (rather than
plain `wasm32`): it imports WASM-4's required `env.memory` and places static
data plus the bump allocator after the console-owned region at `0x19a0`. This
is essential — a self-defined memory or program data at address zero makes the
runtime and cart observe different memory and results in a blank screen.
The profile also retains the mutable allocator global; every target-generated
`alloc4` references it, so omitting that global makes the Wasm validator reject
the cart with `Invalid global index: 0`.

Three compact D-only cartridges dogfood the compiler:

- `demo/wasm4/tetromino.d` — a falling-block toy with movement and gravity.
- `demo/wasm4/minicraft.d` — a block-world scene with a movable placement
  cursor.
- `demo/wasm4/flight.d` — a pseudo-3D horizon and controllable wireframe
  aircraft.

`demo/wasm4/snake.d` is different: it is a D port of the core game mechanics
from the [official WASM-4 Snake tutorial](https://wasm4.org/docs/tutorials/snake/creating-the-snake).
It keeps the tutorial's 20×20 grid
and 8×8 cells, tail-following movement, four-direction gamepad control,
fruit growth, self-collision, and restart-on-button-one behaviour. The cart
uses parallel fixed arrays for the body so that it also exercises D global
array layout, indexed loads/stores, loops, calls, and browser-facing drawing
without JavaScript game logic.

`demo/wasm4/puyo.d` is the first playable, dependency-free d2qbe port inspired
by `wasm4-puyo`. It uses a 6×12 fixed-array board, a deterministic D PRNG,
falling pairs, left/right/rotate/down input, four-or-more flood-fill clearing,
gravity, chain scoring, and restart. It intentionally draws with the already
tested `rect` ABI first; this removes the original cart's unavailable
`env.rand` requirement before adding optional sprite/text polish.

Each exports WASM-4's `start()` and per-frame `update()` callbacks. The
runtime calls `update` about 60 times per second; no JavaScript game logic is
used. Build them all with the existing compiler stages:

```sh
make wasm4-carts
```

To run one cart, install the optional official `w4` command and use one of:

```sh
make wasm4-tetromino
make wasm4-minicraft
make wasm4-flight
make wasm4-snake
make wasm4-puyo
```

`make test` runs `test-wasm4-carts`; it has no `w4` dependency and verifies
all five generated binaries export `start`/`update`, import `rect` and
`env.memory`, and start program data after WASM-4's reserved region. `w4 run`
is a separate interactive runtime check.

### Puyo Puyo compatibility probe

`ShigekiKarita/wasm4-puyo` is the next real-world dogfood target. Its original
D source is a useful fuller game, but it is not a drop-in browser cartridge:
the raw build imports `env.rand`, while the official browser runtime provides
no such function. The port must therefore use a small deterministic D PRNG
rather than add an unofficial JavaScript import.

The initial d2qbe probe also identifies concrete frontend work. `uint` now
lowers as the Wasm i32 word type with a pipeline test. Structs, fixed arrays,
`foreach` ranges, and methods already parse; remaining early surface includes
`ushort`/`ubyte`, static-local storage, and array literal initializers. Import aliases and the
multi-file module arrangement are deliberately deferred: the first cart is
kept as one dependency-free D source beside the existing WASM-4 binding.
Each capability lands only with a focused compiler pipeline test and is then
used by the cart. The intended milestone is a playable falling-pair board
with left/right/rotate/down, gravity, four-or-more clearing, chain score, and
`blit` rendering; this is more valuable than mechanically accepting every
syntax feature before the game has a runnable core.

Both targets use only an already-installed `python3` as a local static server.
Set `WASM_BROWSER_PORT=9000` to choose another port. Set
`WASM_BROWSER_OPEN=0` to serve without opening a GUI, which is useful for
checking generated assets in a non-graphical environment.

`make test` includes `make test-wasm-browser-assets`: it rebuilds the same
fixtures and checks the manifest and both browser pages without requiring a
GUI or leaving a server running.

### Develop a feature test-first

1. Add the smallest failing case to `test/dqbe_wasm_test.sh`. Prefer a D
   pipeline test when the frontend layout matters; add a hand-written QBE
   case when testing a backend opcode or section directly.
2. For binary writer branches, also add a native D `unittest` in
   `source/dqbe/wasm.d`. Use exact bytes for a compact, stable encoding and
   a success/failure assertion for larger modules.
3. Run `make test-dqbe-wasm`; confirm the new test fails for the expected
   reason before changing production code.
4. Implement the narrowest lowering in `source/dqbe/wasm.d` or target-aware
   frontend lowering in `source/d2qbe/codegen.d`.
5. Run `make unittest-frontend`, `make unittest-backend`, and
   `make test-dqbe-wasm`. Before a checkpoint commit, run `make test`.
6. Update this document's implementation status, feature comparison, and
   measured test coverage. Keep commits to one coherent capability.

### Inspect the stage that is actually wrong

Most failures belong to one of three layers. Inspect them separately before
editing code:

| Symptom | First inspection | Likely owner |
| --- | --- | --- |
| `d2qbe -t wasm32` emits `l` addresses or wrong `sizeof` | Print its QBE output and search for `=l`, `loadl`, or `storel` | frontend layout/codegen |
| QBE is `w`-only but `dqbe` rejects it or emits malformed bytes | Feed a minimal hand-written QBE program directly to `dqbe -t wasm32` | Wasm backend |
| Browser instantiation fails | Check imports, export names, and section bytes; then compare with browser error | module/host contract |

Useful commands:

```sh
# Keep the generated QBE so its value/address types are visible.
./d2qbe -t wasm32 'extern(C) int main(int* p) { return *(p + 1); }' > program.qbe
rg -n '=l|loadl|storel|call' program.qbe

# Isolate the backend from frontend lowering.
printf '%s\n' \
  'export function w $main() {' '@start' '  ret 42' '}' \
  | ./dqbe -t wasm32 > direct.wasm

# Inspect structural byte signatures already used by pipeline tests.
od -An -tx1 direct.wasm | tr -d '[:space:]'
```

`w` means an `i32` in this target. A remaining `l` is not a harmless spelling
variation: it can be a real 64-bit integer, so the backend rejects it rather
than silently truncating an address.

### Debug memory, calls, and browser imports

- For memory failures, first check that the frontend emits `w` addresses and
  `loadw`/`storew` or `loadub`/`storeb`. The backend exports `memory` only
  when a module needs it.
- For a host function, start with a fixed signature. For example,
  `extern(C) int host_increment(int value);` becomes `env.host_increment`
  with `(i32) -> i32`:

  ```js
  const { instance } = await WebAssembly.instantiate(bytes, {
    env: { host_increment(value) { return value + 1; } },
  });
  ```

  Every unresolved call needs a corresponding `env` property. Pointer values
  are offsets into the exported linear memory, represented as JavaScript
  numbers. The host owns bounds checks and allocation conventions.
- If a generated module reports an inconsistent import signature, locate all
  calls to that external name. Core Wasm has no variadic imports; calls at
  different arities (currently `fprintf`) need a deliberately designed shim,
  not a relaxed type check.
- If an optional independent tool is installed, use `wasm-validate` or a
  browser instantiation failure as an extra validation layer. Do not add it as
  a required build dependency merely to get a green local test.

### Current self-hosting probe

The useful progress probe is:

```sh
./d2qbe -t wasm32 source/d2qbe/app.d | ./dqbe -t wasm32 > app.wasm
```

It is expected to fail today at the variadic `fprintf` import boundary. This
is a feature-gap probe, not a passing test. Keep it that way until the
fixed-arity diagnostic host ABI has been specified and covered by a failing
test first.

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
- Fixed dispatcher functions returning `w` to emit an unreachable instruction
  after closing the dispatcher loop. This makes the enclosing Wasm function's
  unreachable fall-through explicit, satisfying browser validation for both
  conditional and unconditional control-flow modules.
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
- `make wasm-browser-test` builds a browser-visible runtime suite for all
  twenty existing Wasm pipeline fixtures; `make wasm-browser-demo` builds a
  small interactive host-import demo. These are intentionally separate from
  `make test` because they require a graphical browser and leave a local
  server running.
- No standalone Wasm engine or validator is a repository dependency. Use the
  browser suite or an optional browser, Node, Wasmtime, or WABT installation
  for independent runtime validation.

### Test coverage baseline

LDC `--cov` measurement of the backend unit binary reports 74.0% line
coverage for `source/dqbe/wasm.d` (464/627 executable lines) after fixing
dispatcher validation. This maintains the prior coverage percentage while
adding an executed backend line. `test/dqbe_wasm_test.sh` has twenty pipeline
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
self-hosting work is a fixed-arity diagnostic host ABI for variadic output
calls, followed by the remaining slice and struct-copy address lowering. Each
capability begins with a failing test; do not add an external runtime
dependency merely to make the unit tests pass.
