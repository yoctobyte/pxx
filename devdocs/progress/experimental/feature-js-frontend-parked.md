---
prio: 45  # auto
---

# JavaScript frontend — PARKED (architectural wall on the stated goal)

- **Type:** feature — frontend request
- **Status:** backlog — **PARKED** (2026-07-03, user decision)
- **Owner:** —
- **Opened:** 2026-07-03 (feature request: "JavaScript, supports the Cesium library")

## Why parked (honest scoping)

Two separable problems; the second is a wall for *this* project's architecture.

**1. JavaScript the language — big, but not impossible.**
Dynamically typed, GC'd, prototype-based, closures, exceptions, plus the whole
ECMAScript runtime (Object/Array/String/JSON/RegExp/Promise/…). frankonpiler's
IR is statically typed → native ELF. JS needs a **boxed/tagged value model + a
garbage collector + dynamic dispatch** — effectively a JS *engine*, not just a
parser. Much larger than Zig/C (which map onto the IR directly) and larger than
the Rust plan. A subset is conceivable, but the runtime IS the work.

**2. "Supports the Cesium library" — out of scope here.**
CesiumJS is a **WebGL 3D-globe renderer**. Running it requires WebGL/GPU, DOM,
Canvas, `requestAnimationFrame`, typed arrays, `fetch`/XHR, Web Workers — an
entire **browser + GPU stack**. frankonpiler emits native binaries with none of
that runtime. "Run Cesium" is therefore not a compiler-frontend problem; it is a
"build a browser and a GPU driver" problem, which is outside this codebase's
architecture and goals. (Compiling Cesium *source* as a parse-only coverage
torture test — the way C targets lua/sqlite — is possible but low value, since
it could never run.)

## If revisited, first pin down the actual goal

- **Run Cesium** → needs a browser/WebGL runtime → not achievable in a native
  AOT compiler; would be a separate project (embed an existing engine, or target
  WASM+browser), not a frankonpiler frontend.
- **Compile JS as a language-coverage exercise** (no graphics) → feasible-ish as
  a JS-subset frontend + a tagged-value/GC runtime; scope a non-graphical torture
  test (e.g. a pure-computation JS program), NOT Cesium.
- **A specific non-graphical slice** (e.g. Cesium's geometry/math only, as a
  library port) → scope that explicitly; it is a different, smaller ask.

Preferred new-frontend work is [[feature-zig-frontend]] (C-style, maps directly
onto the IR). Reopen this only with a concrete, runtime-feasible goal.

## Log
- 2026-07-03 — filed and immediately parked per user ("let's park JS"). Recorded
  the architectural wall so the reasoning isn't relitigated from scratch later.

## Verdict confirmed + the actual JS answer (2026-07-09, advice session)

Re-examined with the user after the Zig/Rust "theoretic completion"
passes. The park holds — and gets sharper:

- **A JS skeleton probe would be worthless**: the grammar shapes are
  already covered by the C/Rust probes; the hard part (boxed values, GC,
  prototype dispatch, coercion on every operator) is exactly what a
  skeleton cuts. A frontend where every var is secretly i64 is JS-shaped,
  not JS.
- **The stated goal was never syntax, it was "run interesting JS
  libraries."** That goal is now routed through
  [[feature-c-corpus-quickjs]] (Track C, backlog): compile a real JS
  engine (~85k lines of plain C) with cfront and get full JS — closures,
  prototypes, GC, async, eval — semantics included, because someone else
  already wrote the engine. Same precedent as lispdemo.pas and COBOL's
  interpreter relaxation, scaled up.
- **Cesium et al stay permanently out on every path** — WebGL/DOM is a
  browser ecosystem, not a language. Realistic wins are pure-compute
  libraries (parsers, math, crypto) under the QuickJS route. (User: the
  Cesium wish is really a "would be nice from Python" ecosystem wish —
  beyond any compiler ticket.)
- **The typed-subset idea (TS-strict / asm.js insight) stays unfiled**:
  it compiles fine on the existing IR but real libraries are not written
  in the subset, so it would be a new JS-looking language, not JS. File
  only if that language is ever wanted for itself.
- The statically-compilable neighbor got its own ticket:
  [[feature-wasm-frontend]] (experimental) — different value proposition
  (consume compiled polyglot .wasm, not JS libs).

