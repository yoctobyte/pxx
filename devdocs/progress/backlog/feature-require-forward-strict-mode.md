# `--require-forward` — opt-in FPC-strict declaration ordering (no auto-forward)

- **Type:** feature (parser architecture / FPC-compat) — Track A
- **Status:** backlog
- **Owner:** unassigned
- **Opened:** 2026-06-27
- **Relation:** the enforcement counterpart to
  [[feature-declaration-prescan]] (which made PXX order-independent) and the
  early-warning for [[bug-fpc-seed-helper-ordering-after-lua-c-frontend]]
  (forwards forgotten → seed breaks, only caught at `make bootstrap`). Folds into
  [[feature-mimic-fpc]].

## Problem

PXX's declaration pre-scan registers every top-level header up front, so
call/use-before-define and `forward`-free mutual recursion always compile. FPC
does not: it is single-pass and resolves a routine only if a header is **above**
the call (full def / `forward;` / an `interface` section / a class-record method
decl). So PXX silently accepts source shapes that the FPC cold seed
(`make bootstrap`, `make test-fpc`) rejects. We only discover the gap when FPC
actually runs — slow, and requires an FPC install.

Goal: an **opt-in** mode where PXX enforces FPC's ordering rule, so a normal PXX
compile (no FPC) tells you "this will fail the seed."

## Proposal

- New flag `--require-forward` + source directive `{$REQUIRE FORWARD ON}`,
  setting a global `RequireForward: Boolean` and a compile-time define
  `PXX_REQUIRE_FORWARD`.
- When on, PXX rejects resolving a top-level routine/type/const whose header is
  not "above" the use by FPC's four visibility rules — i.e. it stops honouring
  the pre-scan's forward registrations and emits a real error
  (`<file>:<line>: identifier used before its declaration (--require-forward)`).
- `--mimic-fpc` turns `--require-forward` on as part of its set (mimic ==
  "behave like FPC", and FPC is strict). Also usable standalone.

### CRITICAL: own define, NOT `FPC`

The strict define **must be `PXX_REQUIRE_FORWARD`, distinct from `FPC`.**
`--mimic-fpc` already installs the `FPC` define (see `defs.inc:737`), and `FPC`
activates `compiler.pas:26` `{$ifdef FPC} uses SysUtils, BaseUnix` — FPC RTL
units PXX does not provide. So you cannot reuse `FPC` for strictness without
dragging in SysUtils and breaking the self-build (documented "mimic during
self-build = broken bootstrap"). The forwards.inc guard in
[[bug-fpc-seed-helper-ordering-after-lua-c-frontend]] therefore widens to
`{$if defined(FPC) or defined(PXX_REQUIRE_FORWARD)}`: real FPC pulls SysUtils +
forwards; PXX-strict pulls only forwards, no SysUtils → it can still self-compile.

## Why this is the prize

With forwards.inc gated on `FPC or PXX_REQUIRE_FORWARD`, PXX run with
`--require-forward` includes the **same** forwards FPC sees and reverts to
single-pass resolution → it fails in the **exact same place** FPC's seed would.
That turns "will the cold seed compile?" into a normal, FPC-free PXX compile.
A fast local proxy for `make bootstrap` seed-compat, no FPC install needed.

## Implementation options (pick during build)

- **A — disable the pre-scan when strict.** Skip pass-1 header registration
  (revert to pre-[[feature-declaration-prescan]] single-pass). Most faithful to
  FPC by construction; blunt (big-bang, errors arrive en masse, harder to
  bisect). Gets types/consts strictness for free.
- **B — keep pre-scan, add a position check (recommended).** During pass-1 record
  each top-level symbol's first-header token index (def or `forward`). At resolve
  time, if strict and the use precedes that index (and it is not interface /
  method / `uses`-visible), error. Additive, precise per-site messages, lower
  regression risk, can also be downgraded to a warning. Cost: re-derive the four
  visibility rules in the checker.

Lean B for UX; note A as the simplest faithful fallback.

## Scope decision (call out in build)

FPC ordering strictness covers **types and consts** too (pointer-to-record
defined later, const-before-use), which the pre-scan also masks. The current
compiler source already seeds under FPC (modulo the two routine bugs), so it is
mostly type/const-clean. Decide: routines-only first (covers the known pain), or
full ordering. Recommend routines-first, widen if a type/const seed break shows.

## Acceptance

- `--require-forward` flag + `{$REQUIRE FORWARD ON}` parsed; sets
  `PXX_REQUIRE_FORWARD`.
- Synthetic test: a program with call-before-define (no `forward`) and
  forward-free mutual recursion **compiles without** the flag, **errors with** it
  — at the right line.
- Existing explicit `forward;` still accepted under the flag (no double-flag).
- `--mimic-fpc` implies `--require-forward`; standalone use also works.
- Normal (non-strict) self-host stays **byte-identical** — the flag only changes
  acceptance, never codegen.

## Bonus — FPC-free seed-compat self-test (the extra test)

Add a gate that self-compiles the compiler under `--require-forward` (with
forwards.inc present via `PXX_REQUIRE_FORWARD`): it must compile clean, proving
the source is FPC-seed-ordering-clean **without invoking FPC**. Candidate make
target `test-require-forward-selfhost`.

NB: run this under `--require-forward`, **not** `--mimic-fpc`. mimic defines
`FPC` → `uses SysUtils, BaseUnix` → self-build breaks (defs.inc:737). The
standalone strict flag is the one that both enforces ordering and stays
SysUtils-free, so it is the only one that can actually self-compile. (Compiling
under `--mimic-fpc` would additionally need the `uses SysUtils` line decoupled
from the strictness axis — out of scope; the strict-flag self-test gives the same
ordering signal without that.)

## Landmines

- Do not reuse `FPC` as the strict define (SysUtils trap above).
- Interface-section and class-method headers are "above" by definition — the
  checker must treat them as visible regardless of body order, or it will
  false-positive on every method call.
- Builtins / intrinsics / `uses`-imported symbols are always visible — exempt.
- Nested routines keep lexical inner-after-outer scope; strictness is top-level
  only, matching FPC.

## Log

- 2026-06-27 - Filed. Came out of the FPC-vs-PXX forward-resolution analysis
  while validating the b94 pointer-deref pin (v83). User + agent converged on:
  (1) forwards.inc FPC-gated [other ticket], (2) this strict flag, (3) folded
  into mimic-fpc but standalone, (4) bonus self-compat self-test. No-fix-now,
  ticket only.
