---
track: A
prio: 20
type: feature
blocked-by: []
summary: "TypeInfo(Integer)^.Name returns `Integer` in pxx and `LongInt` in FPC. The underlying type already matches (both 4 bytes on x86-64) — only the string differs. Report `LongInt` under strict-FPC mode and keep `Integer` by default: one new strict flag, one line in EnableStrictFpc, one line in TypeInfoOrdName's case."
status: backlog
owner: unassigned
---

# `TypeInfo(Integer)^.Name` should say `LongInt` under strict-FPC

- **Track A** — `compiler/rtti_emit.inc` + `compiler/lexer.inc` (the strict-flag
  bundle). Small and self-contained.
- Implements [[decide-typeinfo-scalar-name-spelling]], answered by the user
  2026-08-21: *"in strict FPC mode, we just mangle the name 'Integer' to
  'Longint'. we are already compatible about the underlying type. it's just
  naming."*

## What to change

`TypeInfoOrdName` (`compiler/rtti_emit.inc:806`) is a flat `case` over
`TTypeKind`. One row moves:

    Ord(tyInteger):  Result := 'Integer';
    ->
    Ord(tyInteger):  if StrictTypeNames then Result := 'LongInt'
                     else Result := 'Integer';

Add `StrictTypeNames` alongside the other per-behaviour strict flags in
`defs.inc`, and set it in `EnableStrictFpc` (`compiler/lexer.inc:628`) next to
`StrictOperator` / `StrictCase` / `StrictVisibility` / `StrictShiftWidth` /
`StrictVariantChar`.

**Follow that pattern, do not invent a new gate.** There is no single `StrictFpc`
boolean — `EnableStrictFpc` turns on a bundle of individually named flags, so a
new parity behaviour gets its own name and joins the bundle. That is what makes
each one separately testable and separately documentable.

No conflict with the umbrella's contract: `EnableStrictFpc`'s own comment says it
*"does NOT change default name resolution"* — this is an RTTI label, not
resolution.

## Only this one row

Measured against FPC 3.2.2 on x86-64: `Byte`, `Int64` and the rest already match.
`Integer` is the sole divergence, and it exists for a structural reason — FPC's
`Integer` is an alias of `LongInt`, while pxx has `tyInteger` and `tyInt32` as
separate kinds and so has a name of its own to report.

**The widths already agree** (both 4 bytes; native is 8 in both). Nothing about
this ticket changes a type, a size, or a computation — only a string in the RTTI
blob.

## Test

`test/test_typeinfo_named_types.pas` asserts the current answer explicitly and
points at the decision ticket. Extend it to assert **both** directions — `Integer`
by default, `LongInt` under `--strict-fpc` — in the two-row shape
`test_fpc_mem_errors.pas` uses, so a later default flip shows up as a failing row
rather than a silent change.

## Gate

`make compiler/pascal26` + self-host fixedpoint (byte-identical), `tools/gate.sh
quick`. Nothing here reaches a backend.
