---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A typed CONSTANT (or var) array whose low bound is <= -2 has every negative-indexed element written to the array's BASE instead of its slot: `array[-2..2] of Integer = (10,20,30,40,50)` reads back as (20,0,30,40,50). The element index doubles as the \"no element\" sentinel."
status: done
owner: frank1-ACP
---

# `array[-2..2] of Integer = (...)` initialises the wrong slots

- **Track P** (Pascal frontend: the const/var-section initializer record, and the
  emitter that turns it into stores — both in `parser.inc`).
- Found 2026-08-20 by an FPC differential probe while checking the blast radius
  of the unary-minus constant fix. **Pre-existing** — the pinned binary does the
  same, so it is not a regression of that work.

## Repro (values are `fpc -O- -Mobjfpc`'s)

```pascal
const
  A2: array[-2..2] of Integer = (10, 20, 30, 40, 50);
  A5: array[-5..-3] of Integer = (1, 2, 3);
  B1: array[-2..0] of Byte    = (7, 8, 9);
```

| | FPC | pxx |
| --- | --- | --- |
| A2 (read through a pointer at the base) | 10 20 30 40 50 | **20 0 30 40 50** |
| A5 | 1 2 3 | **3 0 0** |
| B1 | 7 8 9 | **8 0 9** |

Reading is fine — a `var` array with the same bounds reads and writes
correctly, `Low`/`High` are right, and the values above were dumped through a
pointer at the base, so the DATA is what is wrong.

## Mechanism — a sentinel living in the value space

`PendingInitElem[i]` (and `LocalInitElem[i]`) carries the array INDEX of an
initializer element, with `-1` meaning "no element, this is a scalar" and `-2`
meaning "address-of-global pointer init". The emitter then asks:

```pascal
if PendingInitElem[i] >= 0 then   { ...build an AN_INDEX node }
```

An array index can be NEGATIVE. So for every element whose index is below zero
the emitter builds **no index node at all** and assigns to the array symbol
itself — the base. `A2`'s -2 and -1 elements both land on slot 0 (the second
overwrites the first), slot 1 is never written, and the elements from index 0
up are placed correctly. That reproduces all three rows exactly, including
`A5`, where all three indices are negative and only the last survives.

A low bound of exactly **-1** is the benign case and is why this went unseen:
the one misplaced element lands on slot 0, which is where it belonged.

## Fix

Move the markers out of the value space — named constants far below any legal
index (`PI_ELEM_NONE`, `PI_ELEM_ADDRG`) — and test against them instead of
`>= 0`. Both readers (`parser.inc`'s global flush and its local-const sibling)
and every assignment of `-1` / `-2` on these two arrays. The C frontend also
fills `PendingInitElem`, but C arrays always start at 0, so nothing there
changes.

This is the same anti-pattern as
[[refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag]]: a field
that is both a value and a flag, where the flag's encoding is reachable by a
legal value.

## Gate

The three rows above match FPC; a test under `test/` pins them plus the
low = -1 case; `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.


## Fixed

`PI_ELEM_NONE` / `PI_ELEM_ADDRG` (defs.inc, far below any legal index) replace
the `-1` / `-2` markers on `PendingInitElem` and `LocalInitElem`, and both
emitters test against them instead of `>= 0`. 17 assignment sites across
`parser.inc` and `cparser.inc`, three readers.

The LOCAL typed-const path had the same defect and the same shape (`const L2:
array[-2..2] of Integer = (...)` inside a routine), which the repro found only
because the test exercises it — the two emitters are separate code with one
convention between them, so a fix to either alone would have left the other
silently wrong.

`test/test_const_array_negative_low_bound.pas`: 38 assertions, every value
`fpc -O- -Mobjfpc`'s own. Before the fix pxx scored 20/38; after, 38/38.
Values are read BOTH by index and as raw memory from the base, so a wrong slot
cannot hide behind a matching wrong index — that is what separated the writer
from the reader during diagnosis (the reader was never wrong).

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
