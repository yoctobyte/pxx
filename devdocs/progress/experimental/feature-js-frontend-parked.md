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
