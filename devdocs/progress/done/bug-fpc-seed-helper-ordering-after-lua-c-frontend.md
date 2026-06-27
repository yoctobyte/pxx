# FPC seed build fails after Lua C frontend helper additions

- **Type:** bug
- **Status:** done
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27 during Track C Lua compiler stability check

## Symptom

`make bootstrap` currently fails in the initial FPC seed compile before the
self-host stages:

```text
symtab.inc(979,27) Error: Identifier not found "TypeSize"
ir.inc(901,15) Error: Identifier not found "CNodeDecaysToPointer"
```

This is not a self-host stability failure. It is an include-order / forward
declaration issue exposed by helper calls added during the Lua C frontend work:

- `RecFieldRowStride` in `symtab.inc` calls `TypeSize` before `TypeSize` is
  declared for FPC.
- `IRNodePointerBase` in `ir.inc` calls `CNodeDecaysToPointer`, but `cparser.inc`
  is included after `ir.inc` in `compiler.pas`.

Self-hosted `compiler/pascal26` has historically accepted this shape, but FPC
does not. Fix should preserve the include model and avoid moving large chunks
unless necessary.

## Root cause (settled 2026-06-27)

FPC is strictly single-pass: at a call site it resolves a routine **only if it
has already seen that routine's header above** in the linear (post-`{$include}`)
text. A header counts as "seen above" exactly four ways: (1) full definition
above, (2) a `forward;` above, (3) it sits in an `interface` section — this
unit's or any `uses`-d unit's (all interfaces compile first), (4) it's a method
published by a `class`/`record` type decl above. None of those → `identifier not
found`. FPC does **not** rescan; it does **not** auto-forward implementation/
program routines; mutual recursion genuinely needs `forward`.

PXX is more permissive: the declaration pre-scan
([[feature-declaration-prescan]]) registers **every** top-level header first, so
order never matters and `forward` is never required. That leniency is what masks
these two seed breaks until `make bootstrap` runs the real FPC.

Both failures are the identical shape — header not above the call:
- `TypeSize` — same file, def at `symtab.inc:1216`, call at `:979`, no forward
  above.
- `CNodeDecaysToPointer` — a `forward;` exists at `cparser.inc:19`, but
  `cparser.inc` is pasted *after* `ir.inc`, so it is *below* the `ir.inc:901`
  call.

(Historical note: the `LowerCase` case that motivated the pre-scan was NOT
whole-section magic — under FPC `LowerCase` came from `SysUtils`' interface
(rule 3); PXX used its own copy defined later. Different routines, not a rescan.)

## Solution (chosen — matches the existing inline-`forward` practice)

`compiler.pas` already hand-maintains unconditional inline `forward;` decls at
include boundaries (`AsmB`/`AsmI16..64` before `x64enc`, `CPreprocess` before
`parser`, `GetOrAlloc*` after `ir`) purely to satisfy FPC's rule — PXX tolerates
a redundant `forward`. These two are simply forwards that were forgotten when the
Lua C-frontend helpers landed.

Fix = consolidate into a new **`compiler/forwards.inc`**, included once *before
`{$include symtab.inc}`* (both signatures use only base / `defs.inc` types, so
that single early point is above both uses):

```pascal
{ FPC-seed-only forward decls. PXX prescans the whole program and never needs
  these; FPC compiles top-down and does. Signatures MUST stay byte-identical to
  the bodies. }
function TypeSize(tk: TTypeKind): Integer; forward;
function CNodeDecaysToPointer(node: Integer): Boolean; forward;
```

Include guard — step 1 ships `{$ifdef FPC}`; widen to
`{$if defined(FPC) or defined(PXX_REQUIRE_FORWARD)}` once
[[feature-require-forward-strict-mode]] lands (so PXX-strict sees the same
forwards and becomes an FPC-free seed proxy).

Then **delete the now-redundant `cparser.inc:19` forward** — `forwards.inc`
provides it earlier; two `forward;` for one routine is an FPC error.

## Acceptance

- `make bootstrap` seeds clean (FPC) past both `Identifier not found` errors.
- Normal PXX self-host stays **byte-identical** (forwards.inc excluded when FPC
  undefined; only change PXX sees is the deleted `cparser.inc:19` line, which the
  prescan already covered).
- Optional: migrate the existing inline `forward;` decls into `forwards.inc` too
  (consolidation) — separate commit, re-verify byte-identical since those are
  currently unconditional and PXX-visible.

## Log

- 2026-06-27 - Captured from failed `make bootstrap` seed compile. User confirmed
  FPC seeding is not required for the current push, but this should be fixed.
- 2026-06-27 - Root cause settled + solution chosen (forwards.inc, FPC-gated,
  remove `cparser.inc:19` dup). Companion strict-mode flag filed as
  [[feature-require-forward-strict-mode]]. Not fixed yet (no-fix-now, ticket
  only).
- 2026-06-27 - FIXED + verified. forwards.inc (FPC-gated) + two `;` in CompilePendingGlobalInits. `make bootstrap` green end-to-end, `make test` self-host byte-identical. Strict-mode enforcement = separate [[feature-require-forward-strict-mode]].
