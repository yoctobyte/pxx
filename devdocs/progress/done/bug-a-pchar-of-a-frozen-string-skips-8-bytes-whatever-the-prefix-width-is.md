---
prio: 88
track: A
type: bug
status: done
summary: "A frozen string reaches a `Pointer`/`char*` through FIVE arms that each hardcode +8 for the length prefix behind a `= tyString` guard, and BOTH halves are wrong: the width is 1 under -dPXX_SHORTSTRING, and the guard misses an array element or record field, which carry the kind the aggregate records. Not flag-only -- in the DEFAULT mode `Take(arr[0])` handed the callee the length prefix and `Take(@r.f)` handed it base+8 for an address-of. Fixed: 21 assertions x 7 targets x both modes (xtensa both ABIs), positive control fails without it."
owner: frankB
---

# PChar of a frozen string skips 8 bytes whatever the prefix width is

```pascal
type TS = string[8];
var s: TS; arr: array[0..1] of TS; r: record f: TS; end;
begin
  s := 'abcde'; arr[0] := 'abcde'; r.f := 'abcde';
  Show(PChar(s));       { default: [abcde]   -dPXX_SHORTSTRING: []      }
  Show(PChar(arr[0]));  { default: [abcde]   -dPXX_SHORTSTRING: []      }
  Show(PChar(r.f));     { correct in both — a different path            }
end.
```

Measured 2026-09-03 on x86-64. It is not a regression: the pin cannot show it,
because `-dPXX_SHORTSTRING` is a no-op in a compiler that predates the layout —
**check `SizeOf` beside any pinned measurement of byte-prefix behaviour**, the
pin prints 16 where the flag mode must print 9.

## Where

Four sites in `compiler/ir.inc` (the auto-`char*` marshalling for a Pointer
parameter, the same for a variadic slot, the function-pointer path and the
virtual-call path) share one shape:

```pascal
if (not isRefArg) and (cpi >= 0) and
   (IntToTypeKind(IRTk[value]) = tyString) and
   ... Params[pathIdx].TypeKind = tyPointer ...
then
  aval := IRAppend(IR_BINOP, aval, IRAppend(IR_CONST_INT, ..., 8, ...), Ord(tkPlus), ...)
```

Two defects in one expression and they need fixing together:

1. **The literal 8** must be `FrozenStrPrefixSize(IRStrTkOf(value))`. That is
   the whole bug in the flag mode.
2. **The guard** is `= tyString`, so it also misses a value already tagged
   tyFixedString or tyShortString — which is what an array element and a record
   field now carry. `TypeIsAnyString` / `TypeIsFrozenString` is the question
   being asked.

`FrozenStrPrefixSize` exists precisely so a literal 8 on a string-ish line is a
countable worklist; these four are on it.

## Why it matters past the flag

`PChar(s)` is how every C binding takes a Pascal string. Under phase 4 this is
the default layout, and the failure is silent: the callee sees an empty string,
not a crash.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## Prio raised 65 -> 88 and wired as a P4 BLOCKER (coordinator, 2026-09-03)

**This gates the flip.** P4's definition of done is deleting
`-dPXX_SHORTSTRING`, i.e. making the 1-byte prefix THE layout — at which point
`PChar(s)` is wrong for **every** `string[N]`, on **every** target, permanently.
frankb-78's own framing is the reason: *"it is how every C binding takes a
Pascal string."*

Today it is a defect behind a flag most programs never set. **After the flip it
is the default behaviour of the interop path**, and it fails in the worst
direction — the callee sees an empty string rather than crashing, because it
lands seven bytes into a NUL-padded tail.

Left at 88 rather than higher because it is not wrong in what ships today; the
flip is what promotes it. Wired `blocked-by` on the P4 ticket so the ranker
carries that rather than this paragraph.


## RESOLVED (frankB, 2026-09-03) — five arms, and the ticket described one of them

The report was right about the mechanism and short by two arms and one mode.
Measured on x86-64 with a walker that prints the bytes a callee actually sees,
then on all seven targets in both modes.

### What was actually broken

| spelling | default | -dPXX_SHORTSTRING |
| --- | --- | --- |
| `f(PChar(s))`, `f(PChar(arr[0]))`, `f(PChar(p^))` | ok | **empty** |
| `f(PChar(r.f))` | ok | **`#5` + the chars** |
| `f(arr[0])` implicit to a `Pointer` param | **`#5` + the chars** | ok |
| `q := PChar(x)` for all four spellings | ok | **wrong for all four** |
| `Take(@r.f)` — an ADDRESS-OF as an argument | **base+8** | **base+prefix** |

Three of those five rows are in the DEFAULT mode, so this was never a
flag-gated defect; the ticket's own repro could not show them because it only
tested the `PChar` cast as a call argument.

### The five arms

1-4. `ir.inc` call-argument marshalling (Pointer param, variadic slot,
   function-pointer call, virtual call): guard -> `TypeIsFrozenString`, literal
   8 -> `FrozenStrPrefixSize(IRStrTkOf(value))`, exactly as the ticket
   prescribed. Fixes `f(arr[0])` in both modes.
5. **`AN_CAST`'s PChar arm (`ir.inc`, the `ASTIVal = -2` sentinel), which the
   ticket did not name.** Same two halves, asked of `ASTTk` instead of `IRTk`.
   This is the arm the `q := PChar(x)` rows need; a call-argument probe cannot
   see it, because arm 1-4 rescues the cast downstream whenever arm 5 declined
   to fire. **The record-field row read GREEN through a call for exactly that
   reason** — one arm silently covering for the other, on one spelling.
6. **`AN_ADDR`, a defect the fix would otherwise have widened.** `@r.f` and
   `@arr[0]` lower to IR_FIELD / IR_INDEX tagged with the aggregate's string
   kind, and arms 1-4 fire on that tag — so an ADDRESS-OF argument got the
   prefix added to it. `@s` was correct only because IR_LEA on a symbol already
   yields tyPointer, so three spellings of one operation disagreed. The arm
   already retagged the float case with the sentence *"the address VALUE is a
   pointer no matter what it points at"*; this applies it where it was equally
   true. Without it, widening the guard in 1-4 would have broken `@arr[0]` too —
   the fix's own regression, caught by an offset row in the new test.

### The instrument that lied

`Show(PChar(r.f))` printed `[abcde]` while the pointer was one byte low: the
first byte was `#5`, invisible in a terminal, and the row was read as a PASS.
The regression test asserts `walked = 'abcde'` rather than rendering it, and the
control run prints `[<005>abcde] FALSE` — the same bytes, now a failure.

### Verification

- `test/test_pchar_of_a_frozen_string.pas` — 21 assertions: cast / implicit /
  **assignment** spellings x var / element / field / deref / literal /
  AnsiString, four offset rows asserting the RELATION
  `PChar(x) - @x = SizeOf(TS) - 8` (no width in the expected output, so ONE
  .expected serves both modes and the default mode is a real control, not a row
  that passes for the old reason), a must-not-fire pointer-cast control and a
  must-differ second element.
- 7 targets x 2 modes, xtensa both ABIs: 16/16 MATCH.
- Positive control: fix stashed, stamp removed, rebuilt (c55894ef5e11) — fails
  in BOTH modes; restored (b9a8bb0c5f2c) — MATCH.
- FPC 3.2.2 rejects every frozen spelling in the file
  (`Illegal type conversion: "TS" to "PChar"`), so there is no oracle here and
  the expected output is pxx's own. Recorded in the test's header.
- Wired: native, i386, riscv32, wasm32, both modes each.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 61b12b89c.
