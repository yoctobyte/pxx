---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`d := s` for `d: array of LongInt` and `s: array[0..2] of LongInt` stored the STATIC array's ADDRESS into the dynamic array's handle slot, so Length read the words in front of `s` as a managed-block header — measured `Length(d) = 4310328` and a SEGFAULT walking it, where fpc prints `len=3: 2 4 6`. Silent garbage then a crash, from four lines of ordinary Pascal. The kind check cannot see it: an array symbol's TypeKind is its ELEMENT's kind, so both sides are tyInteger and AssignKindsIncompatible sees a matching pair. NOW REFUSED by name (cb250faf6052) so the crash is a diagnostic; the COPY fpc performs is still missing, and the route is already in the tree."
status: backlog
owner: unassigned
---

# A static array assigned to a dynamic array stores its address

- **Found:** 2026-09-06 (frankS), looking for a way to materialise a static
  array for tarray12's eleventh check. Not an Insert bug — reachable from plain
  assignment.
- **Measured at compiler `63c65f442a69`** against fpc 3.2.2; refusal landed at
  `cb250faf6052`.

```pascal
var d: array of LongInt; s: array[0..2] of LongInt;
begin
  s[0] := 2; s[1] := 4; s[2] := 6;
  d := s;                    { fpc: len=3: 2 4 6   pxx: len=4310328, then SIGSEGV }
end.
```

Both spellings of the source did it — a named `TS = array[0..2] of LongInt` and
an anonymous `array[0..1] of Byte`.

## The three neighbours, and why only one is wrong

| | | |
| --- | --- | --- |
| `d := e` dyn -> dyn | **correct** | must stay |
| `t := o` OPEN ARRAY param -> dyn | **correct**, and **fpc REJECTS it** | us accepting what fpc rejects is not a defect; must stay |
| `d := s` FIXED -> dyn | **garbage, then SIGSEGV** | this row |

## The route for the real fix is already in the tree

The open-array row works for a reason that is the blueprint: **the open-array
marshalling temp already carries `[len:8][data]`**, which is exactly the header
a dynamic array's handle slot wants. A static source wants materialising the
same way — `IRLowerCallArg` already builds it for an open-array argument — not
a new ABI.

**The same missing materialisation is tarray12's eleventh check**: `Insert(t3,
t, 2)` with a static `t3` gives `0, 1, 4680456, 2, 3, 4`, because
`PXXDynInsArrFill` reads the inserted length via `PXXDynLen(insData)`, from the
header at `[data-8]`, which a static array does not have. One materialisation
closes both; do not fix them separately.

## What the refusal deliberately does NOT cover

A static array **parameter** assigned to a dynamic array. `AllocParam` stamps
`ArrLen := 1000` on EVERY array parameter as the open-array placeholder, so a
parameter's recorded length is not trustworthy in either direction, and the
guard keys on `Kind <> skParam`. A guard that fires on an unreliable reading is
worse than one that misses. The local and global case is what was measured to
crash.

**`ArrLen > 0` does not mean "fixed length"** — the first version of the guard
tested exactly that and refused the open-array row. Its positive control,
`test_an_open_array_parameter_still_assigns_to_a_dynamic_array`, is a file that
must COMPILE, and it caught it.
