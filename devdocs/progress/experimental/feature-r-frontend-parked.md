---
prio: 45  # auto
---

# R frontend — PARKED (dynamic-runtime language, not a math overlay)

- **Type:** feature — frontend request
- **Status:** backlog — **PARKED** (2026-07-04, user decision)
- **Opened:** 2026-07-04 (feature request — considered as a frontend candidate)

## Why parked

Initial expectation was that R is a thin **mathematical/statistical syntax
overlay** — cheap to add like a C-family frontend. It is not. R is a full
**dynamic-runtime language**, in the same bucket as JavaScript
([[feature-js-frontend-parked]]), NOT the Zig/Rust "C-compatible syntactic
sugar" bucket that maps straight onto the shared static IR.

What makes it a runtime project, not a frontend:

- **Dynamically typed** — variables hold any type → needs a **boxed/tagged
  value model + garbage collector**. Does not map onto the statically-typed IR
  the way C/Zig/Rust do.
- **Vector-first** — the atomic unit is a vector (a scalar is a length-1
  vector); elementwise ops + recycling rules → needs a **vector engine**.
- **Copy-on-modify** — pass-by-value with copy-on-write, refcounted (our ARC is
  only a partial precedent).
- **Lazy args + non-standard evaluation** — function args are promises;
  functions capture *unevaluated* argument expressions (`quote`/`substitute`/
  `eval`). Runtime metaprogramming, and **pervasive** — the tidyverse
  (dplyr/ggplot2) is built on it. Cut it and you can't run most real R.
- **`NA` missing values** propagate through every type/op.
- **The value IS the ecosystem** — base R + stats + CRAN, most heavy packages
  being **C/Fortran** with R glue. "Support real R" implies that stack — the
  same JS/Cesium-style wall.

## The real fork (shared with JS)

R's question is not "R yes/no" — it is **"do we want a dynamic-value runtime
(tagged values + GC) at all?"** That runtime is the big shared investment for
BOTH R and JS; the C-family frontends (Zig/Rust) never need it. So:

- **C-sugar frontends** (Zig, Rust) — tractable, map onto the IR, near-term.
- **Dynamic-runtime languages** (JS, R) — gated behind the one runtime decision.
  Build it once → both reachable; skip it → both parked.

## Reopen only with

- A concrete pure-numeric R **subset** goal (scalar/vector math + functions +
  control flow, no NSE, no data.frames, no CRAN) with a real target program, OR
- A decision to build the dynamic-value runtime (then sequence R + JS together).

## Log
- 2026-07-04 — parked per user ("forget about R; thought it was a math overlay,
  it's more complex"). Recorded the runtime-vs-overlay reasoning + the
  shared-with-JS runtime fork so it isn't reargued from scratch.
