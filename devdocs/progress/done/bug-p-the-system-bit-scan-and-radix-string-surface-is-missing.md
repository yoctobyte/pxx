---
summary: "`BsfQWord` / `BsrQWord` (and the Byte/Word/DWord widths) and `OctStr` / `BinStr` do not exist — FPC declares all ten in System, and its own compiler stops on two of them"
type: bug
track: P
prio: 45
status: done
---

# The System bit-scan and radix-string surface is missing

- **Type:** bug (RTL surface gap) — Track P
- **Opened:** 2026-08-27
- **Found by:** the FPC-compiler corpus march. `cutils.pas:960` (`ispowerof2`)
  needs `BsfQWord`; `cutils.pas:1092` (`octal_quote`) needs `octstr`. After the
  five frontend fixes that preceded this one, they were the **only** two things
  left in that unit.

FPC declares the bit scan and the radix-string formatters in the **System**
unit, so portable source calls them with no `uses` line. pxx had `HexStr` (in
`builtin`, pulled ambiently) and neither of its siblings, and no bit scan at all.

## Fix

`compiler/builtin/builtin.pas` — ten functions beside the existing `HexStr`:

- `OctStr` / `BinStr`: `HexStr`'s loop with a different mask and shift. Kept as
  three separate loops rather than one radix parameter, because that is how FPC
  spells the surface and a shared helper would have to take the digit table
  anyway.
- `BsfByte` / `BsrByte` / `BsfWord` / `BsrWord` / `BsfDWord` / `BsrDWord` /
  `BsfQWord` / `BsrQWord`.

**The zero case is the point.** All eight answer **255** for a zero argument — a
sentinel, not an index — which is why these cannot be a `log2`, and why FPC
names them by width instead of overloading: the width decides the answer, so
leaving it out would silently widen and return a plausible wrong number. That is
the same argument the `Lo`/`Hi` note in this file already records. Handled
before the loop, so the loop itself needs no exhaustion guard.

`compiler/pasparser_prog.inc` — the ten names join `hexstr`/`random`/`runerror`
in the ambient `builtin` scan, under the same call-shape rule (a following `(`).
A unit reaches them already: any program with a `uses` clause pulls `builtin`.

## Outcome — FIXED, 2026-08-27

`test/test_bitscan_and_radix_str.pas` (wired into `test-core`) is
**byte-identical to the FPC 3.2.2 oracle** across eleven rows: all four widths
of `Bsf`/`Bsr` with zero, one, a mid value and the top bit set; `OctStr`
truncating and padding; `BinStr` including the degenerate zero-width; and FPC's
own `ispowerof2` transcribed verbatim from `cutils.pas:953`, exercised on a
power of two, a non-power, and zero.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

## Corpus march — cutils.pas COMPILES

**FPC's `cutils.pas` now compiles clean, end to end**, 1500+ lines of FPC's own
compiler source, with two `duplicate definition` warnings and no errors. The
pinned compiler stops at **line 58**.

Six fixes got it there, all this session and all closed:
`bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed` (331 → 463),
`bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units`
(463 → 960), `bug-p-a-shortstring-function-result-prints-as-a-pointer`,
`bug-p-a-frozen-string-concat-operand-becomes-pointer-arithmetic`,
`bug-p-index-0-of-a-frozen-string-is-not-the-length-byte` and
`bug-p-inc-dec-does-not-accept-the-enclosing-functions-own-name` (960 → 1429 →
clear), then this one.

## Flagged, not built

**`PopCnt` is still missing.** FPC's is a single **overloaded** name across
Byte/Word/DWord/QWord, not four spellings, so it is not the same shape as the
eight above — it needs overload resolution to pick the width, and picking wrong
is a silently plausible wrong count. `cutils.pas` does not use it. Worth doing
with the overload set thought through rather than as a rider here.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
