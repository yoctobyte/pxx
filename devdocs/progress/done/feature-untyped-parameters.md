# Untyped `var` / `const` / `out` parameters

- **Type:** feature (language / parameter passing)
- **Status:** DONE (Track A) — 2026-06-22. `Move`/`FillChar` RTL bodies are the
  Track B follow-up ([[feature-synapse-compile-check]]).
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Closed:** 2026-06-22
- **Driver:** [[feature-synapse-compile-check]] — `Move` / `FillChar` (and much
  FPC RTL) are declared with untyped parameters; PXX cannot express them as
  ordinary library functions until this lands. Decision recorded with the user:
  do this (option A, library-first / correctness-first) rather than hardcode
  `Move`/`FillChar` as compiler intrinsics (option B, a possible later speed
  path).

## Problem

FPC `Move(const Source; var Dest; Count)` / `FillChar(var X; Count; Value)` use
**untyped** reference parameters — `var`/`const`/`out` with NO type. The caller
passes the address of any-typed lvalue; the callee reaches the bytes via `@X`.
PXX's parameter parser requires a type after every name (`Expected ":"`), so
these can't be written as plain Pascal. This blocks `Move`/`FillChar` and any FPC
source using untyped params.

## Design

An untyped param is modelled as an existing **by-reference (`var`) param** with a
placeholder type (`tyPointer`) plus an "untyped" marker:

1. **Parser** (proc param loop, parser.inc ~9812): after the name list, if the
   next token is not `:`, treat it as untyped — require `var`/`const`/`out`
   (a typeless value param is meaningless), set `tk := tyPointer`,
   `isByRef := True`, and a per-param `puntyped` flag.
2. **Marker plumbing:** `puntyped[i]` -> new global
   `ProcParamUntyped[procIdx*16+i]` (mirrors `ProcParamIsConst`).
3. **Overload match** (MatchProcCall / MatchProcCallInUnit, symtab.inc): an
   untyped param matches ANY argument type (skip the type-compat check for that
   slot).
4. **Call site:** the by-ref path already passes the argument's address
   (`@arg`), and `@x` on a `var` param already yields the referent address
   (verified) — so the callee body uses `@Source` / `@Dest`. No new marshalling.

## Then (Track B, not this ticket)

With untyped params available, `Move` / `FillChar` become small `lib/rtl`
functions over an overlap-safe byte move + a byte fill, auto-loaded so they
resolve without `uses` (System surface). NOTE the existing internal
`PXXMemMove` (builtinheap) is forward-only (memcpy) — `Move` must be
overlap-safe (memmove): copy backward when `dst > src` and the ranges overlap.
Only `PXXMemZero` exists; a general byte-fill is needed for `FillChar`.

## Gate

`make test` (self-host byte-identical — the compiler's own source uses no untyped
params, so it stays byte-identical) + `make cross-bootstrap`. Add a test
exercising untyped `var`/`const` params (a hand-written mem-move/fill over `@x`),
FPC objfpc oracle-matched.

## Log

- 2026-06-22 — opened; design locked with user (option A). Research findings:
  PXX rejects typeless params; `@varparam` yields the referent address (works);
  `PXXMemMove` is memcpy not memmove; only `PXXMemZero` exists.

- 2026-06-22 — **DONE** (landed aafd222). Implemented as designed. Parser accepts a typeless
  `var`/`const`/`out` param (no colon) -> `tyPointer` + by-ref + `puntyped`
  marker (parser.inc, proc param loop); plumbed to `ProcParamUntyped`
  (defs.inc) at both registration sites. MatchProcCall / MatchProcCallInUnit
  accept ANY argument type for an untyped slot (9 bypass sites across the
  exact/compatible/interface phases). The by-ref path passes the arg address and
  `@x` recovers it, so callee bodies use `@Source` / `@Dest`. Test
  `test/test_untyped_params.pas` (untyped `var` fill + untyped `const`/`var`
  move over `PByte(@x)`), FPC objfpc oracle-matched. make test (self-host
  byte-identical — compiler source uses no untyped params) + cross-bootstrap all
  green. **Track B can now write `Move`/`FillChar` in `lib/rtl`** (overlap-safe
  move + byte fill; auto-loaded for no-`uses` availability).
