# Frontends & targets — strategy notes (brainstorm, not a task list)

_2026-06-17. A thinking document, deliberately NOT a ticket. Captures how we
reason about "supporting another language" and "adding another target" so the
decision logic is recorded. Tasks that fall out of it become their own tickets._

## Two axes people conflate

"Support language X" hides two unrelated questions:

1. **Use a library written in X** — no frontend needed.
2. **Compile programs written in X** — needs a frontend.

Keep them apart. They have completely different costs.

### Axis 1 — using a library (no frontend)

- Library exposes a **C ABI** → **FFI it.** PXX already has an FFI: `external`
  decls + dynamic-symbol loading, done on all 4 Linux targets
  (external-C-calls + dynamic symbols). Rust can `extern "C"`, C++ via an
  `extern "C"` shim, C trivially. C# effectively can't (needs the CLR).
- No C ABI → **port the source** to PXX, or wrap it in a thin C shim.
- **Never "emulate the language's runtime"** just to use one library. That is
  the trap, and it is almost never the right answer.

### Axis 2 — compiling a language (frontend)

Only worth it if you want to *author programs* in that language, not merely
consume one library. Parsing is the trivial part. The cost is **semantics**:

1. **Type system / semantic analysis** — unbounded. Rust borrow-checker, C++
   templates, Java/C# runtime generics.
2. **Runtime + GC + object model** — JS prototypes, Java/C# objects, Lisp
   cons+GC, closures over mutable state.
3. **Stdlib / ecosystem** — see the reframe below; for PXX this is mostly
   *solved already*.

## The ecosystem reframe (important)

A per-language stdlib (JDK / BCL / npm) is NOT our ecosystem.

**PXX's ecosystem = the Linux kernel ABI + every `.so` on the system.** Any
application links anything it wants via the existing FFI. The
"kernel-ABI-only / no execve" rule is a **self-host constraint** on the compiler
(proven we don't need libc to bootstrap — a clean result), **not** an
application constraint. Apps are unconstrained.

Consequence: bucket-3 (ecosystem) largely **dissolves** for PXX. A frontend's
cost is then bucket-1 + bucket-2 — the language's *semantic core* — not cloning
a standard library. The libs that code calls are just system `.so`s via FFI.

## Cost taxonomy for candidate frontends

- **C** — closest to the IR (static, value+ptr, manual memory, C-ABI we already
  emit). Already partial (see plan-c-header-import.md, c-interop.md). The one
  "real language" we're already positioned for; ecosystem = its native C ABI =
  what the backend speaks. Highest-ROI real-language frontend. Bounded cost
  (preprocessor, full type rules).
- **Rust (subset)** — more viable than first assumed, because system-lib FFI
  covers the ecosystem need. Remaining cost = the semantic core: borrow-checker
  + traits + monomorphization. Drop those and it's "C with nicer syntax" — not
  meaningfully Rust. Build only to *author* in it.
- **C# (subset)** — cost = GC + runtime generics + delegates (bucket 2).
- **Java** — weakest: object model + GC, and the language only shines with the
  JVM ecosystem we'd skip anyway.
- **Lisp / Scheme** — as a *compiled* frontend needs GC, tagged/boxed values,
  closures, tail calls (Scheme: full continuations). The runtime IS the
  language. Sane path = **nil-lisp**: a typed static dialect in the nil-* family
  (cf. nil-python), sharing our runtime — NOT full RnRS.
- **JavaScript** — full compat = V8-grade, no. **nil-js** static subset = same
  story as nil-lisp. Non-compat JS has weak appeal (people want JS *for* npm /
  browser).

### Reusable insight — shared runtime capability layer

Bucket-2 cost is *shared across dynamic frontends*. Build GC + boxed/tagged
values + closures **once** and every dynamic dialect (nil-lisp, nil-js, …) rides
it cheaply. So dynamic frontends should wait behind that foundation, not each
reinvent it. (See garbage-collection-thoughts.md.)

## Targets vs frontends

A target is orthogonal to all frontend work: lower the existing IR to a new
backend, and *every* frontend gets it free.

### WebAssembly as a target (not a frontend)

wasm = portable **stack-machine bytecode**, sandboxed, runs in browsers +
standalone runtimes (wasmtime / wasmer / node). As a PXX target we'd emit wasm
modules instead of ELF. Properties vs our register ISAs:

- **Stack machine, no registers** — push/pop operands; reg-alloc bypassed.
- **Structured control flow ONLY** — no arbitrary jumps; `block`/`loop`/`if`
  with break-to-depth. Our IR's gotos/labels must be **relooped** (CFG →
  structured blocks, Stackifier/Relooper). This is *the* one real codegen
  wrinkle — an algorithm, not a mountain.
- **Linear memory** — one flat byte array; pointers = offsets. Clean map.
- **No syscalls** — I/O via *imports*. **WASI** (WebAssembly System Interface)
  is the syscall-equivalent ABI; target WASI for stdio/files, or browser imports
  for DOM.

Why attractive:
- One more "ISA" → every frontend runs in a browser sandbox + any wasm runtime;
  arch-neutral distribution.
- **Validates the IR is truly target-independent** — a stack machine is
  maximally different from our register backends; clean lowering proves the
  abstraction.
- Bounded scope: reloop pass + codegen + module writer. No GC/runtime work
  unless we opt into GC-proposal wasm (skip).

ESP32-via-wasm is niche; ignore for now.

## Current read (subject to change — this is brainstorm)

Priority order, per user (2026-06-17):

- **C frontend — HIGH WIN, top priority.** Opens a Valhalla of libraries. The
  whole C world becomes importable, not just FFI-linkable. Already invested
  (plan-c-header-import.md, c-interop.md); ABI is our native tongue.
- **ESP32 focus > WebAssembly.** Embedded is the user's actual interest. wasm is
  confirmed *doable* (reloop + emit + WASI) — and precisely *because* it's
  doable and bounded, it becomes a **low-priority** ticket we can pick up
  anytime, not an urgent one. Park it.
- **Rust/C# subset frontends** — viable *if* we want to author in them (ecosystem
  handled by system-lib FFI); cost is the semantic core. Defer.
- **Dynamic dialects (nil-lisp / nil-js)** — only after a shared GC/boxed-value
  runtime layer exists.
- **Java** — weakest; skip.
- **Using any specific library** — orthogonal: FFI (if C-ABI) or port. Never
  reimplement a runtime for it.

## North-star workflow — "write to upload in seconds" (embedded)

The practical vision that ties C-frontend + nil-python + ESP32 together:

> Write code in **Python-like syntax** (nil-python). **Import any library you
> want** — including C / Arduino libraries — without hand-redefining it. **Don't
> worry about typing**: the compiler auto-detects/infers types. Build an ESP32
> binary in **1–2 seconds**; IDF linker takes maybe another second. From writing
> code to uploading: **seconds**, not the minutes the Arduino/C++ toolchain
> costs.

The selling point is **iteration speed** on embedded, where the incumbent
(Arduino IDE / slow C++ toolchain) is painful. PXX is already fast (near
single-pass), so sub-second compile is realistic.

### What this needs (pulls several arcs together)

- **C header / library import** — so `import <somelib>` pulls a C/Arduino lib
  with no hand-redefine (the C-frontend / header-import arc). The big enabler.
- **Type inference across the FFI boundary** — nil-python is untyped at the
  surface; the compiler infers. Callee-return inference + auto string→`const
  char*` already partly landed (see wrapper-free-c-from-nil-python.md). Extend
  to cover Arduino-shaped APIs.
- **Fast ESP32 build path** — already have Xtensa + RV32 codegen + the ESP/IDF
  integration; keep the compile step sub-second and lean on IDF only for the
  final link.

### Arduino reality — it's mostly C, with a thin C++ subset

Arduino is marketed as C++, but in practice:

- The **core + most libraries are C-like**, or use only a **narrow C++ subset**:
  classes with methods (`Serial.begin()`, object instances), C++-style comments,
  a few conveniences (references, default args, simple overloads). Occasional
  templates, rarely deep.
- Heavy C++ (templates-as-metaprogramming, STL, exceptions, RTTI, multiple
  inheritance) is **uncommon** in this ecosystem.

Implication: a **C frontend + a thin C++ subset** (classes/methods, references,
default args, simple overloads, `//` comments, `namespace`) unlocks the large
majority of Arduino/embedded libraries — *without* paying for a full C++
front end. Classes/methods/VMT we already have on the PXX side
(project_gtk_gui_arc), so the object model exists; the work is the C++ *surface*
mapping onto it, scoped to what these libraries actually use. Audit the real
subset (cf. c-skipped-features-audit.md) before committing scope.

This is the concrete, high-value direction: C frontend (Valhalla of libs) +
thin Arduino-C++ subset + nil-python ergonomics + fast ESP32 build = a uniquely
fast embedded authoring loop.

## If/when these become tasks

Spin out separate tickets, e.g. `feature-target-wasm` (reloop + emit + WASI),
or extend the existing C-import line. This doc stays the rationale; tickets stay
the to-do.
