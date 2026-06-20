# Str() builtin breaks for float formatting when a unit shadows Copy

- **Type:** bug
- **Status:** backlog — **NOT REPRODUCIBLE on pinned v25 / live; needs the lib agent's exact failing source or close**
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced while implementing `FloatToStr` in feature-rtl-conversion-and-bitset-library. Workaround already applied there. Mechanism context: [[design-overloadable-intrinsics]].

## Problem

The compiler's `Str` builtin for float formatting — `Str(d:width:decimals, s)` —
emits a semantic error when any `uses` unit declares its own `Copy` function.
The error message is:

```
Str: expected integer decimals after : ()
```

The `Str` builtin's codegen for the float-width-decimals form internally relies
on intercepting a `Copy` call. When a user-declared `Copy` (e.g. in
`sysutils`) shadows that intercept, the compiler can no longer resolve the
decimal-count argument and fails.

## Reproduction

```pascal
program repro;
uses sysutils;  // declares function Copy(...)
var
  d: Double;
  s: AnsiString;
begin
  d := 3.14;
  Str(d:0:2, s);  // ERROR: Str: expected integer decimals after : ()
end.
```

Without `uses sysutils` the same `Str(d:0:2, s)` compiles and works correctly.
The integer form `Str(i:width, s)` is unaffected — only the float
width:decimals variant breaks.

## Root cause

The `Str` float-decimal codegen path internally emits or expects a `Copy`
symbol that the compiler intercepts. When `Copy` is redeclared in a `uses`
unit, the intercept binds to the wrong symbol (the user's `Copy` instead of
the compiler's internal one), and the decimal-count operand is lost.

## Workaround

Avoid `Str` for float formatting when `sysutils` (or any unit declaring
`Copy`) is in scope. Implement float-to-string conversion manually using
`Trunc`/`Frac`/`Round`, as done in `lib/rtl/sysutils.pas FloatToStr`.

## Fix direction

The compiler's `Str`-builtin codegen should resolve `Copy` against the
compiler's internal symbol table, not the user-visible namespace, so that a
user-declared `Copy` cannot break the intercept. Alternatively, emit the
float-decimal conversion inline without relying on a `Copy` intercept at all.

## Log
- 2026-06-20 — opened. Discovered while implementing `FloatToStr` in
  sysutils.pas; worked around with manual Trunc/Frac/Round conversion.
- 2026-06-20 — **Track A: cannot reproduce on pinned v25 or the live compiler.**
  The exact ticket repro (`uses sysutils;` — which DOES declare
  `function Copy(const s: AnsiString; index, count: Integer): AnsiString` at
  sysutils.pas:22/97 — plus `Str(d:0:2, s)`) compiles and runs, printing the
  correct `3.14`. The `Copy` resolution is `procIdx`-gated so the user routine
  and the dynarray intrinsic no longer collide (see
  [[design-overloadable-intrinsics]]). Either fixed since the v20-era filing or
  the original repro was incomplete. NEXT: lib agent to supply the precise
  failing source (specific arg shapes / nested `uses` order), else close.

## CLOSED (non-reproducible) 2026-06-20 — pinned v26

Re-verified on v26: the exact repro (`uses sysutils` declaring `Copy` + `Str(d:0:2, s)`)
compiles and prints `3.14`. The `Copy` resolution is procIdx-gated so a user
`Copy` and the dynarray intrinsic no longer collide ([[design-overloadable-intrinsics]]).
No failing source was supplied since the v20-era filing. Closing as non-repro;
reopen with exact failing source (arg shapes / nested uses order) if it recurs.
