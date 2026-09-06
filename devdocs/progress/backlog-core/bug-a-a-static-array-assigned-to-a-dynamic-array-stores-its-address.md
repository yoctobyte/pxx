---
track: A
prio: 30
type: bug
blocked-by: []
summary: "`d := s` for `d: array of LongInt` and `s: array[0..2] of LongInt` stored the STATIC array's ADDRESS into the dynamic array's handle slot, so Length read the words in front of `s` as a managed-block header — measured `Length(d) = 4310328` and a SEGFAULT walking it, where fpc prints `len=3: 2 4 6`. The kind check cannot see it: an array symbol's TypeKind is its ELEMENT's kind, so both sides are tyInteger and AssignKindsIncompatible CERTIFIES the pair rather than merely missing it. FIXED: the source is materialised through the array constructor `d := [1, 2, 3]` already uses, so the elements go through the normal element-assign path with coercion and managed-element ARC. Every lo=0 row diffed against fpc 3.2.2. Also closes tarray12 (its eleventh check, `Insert(t3, t, 2)` with a static source, through the same call). RESIDUAL, refused rather than silently wrong: a multidim source, a dyn-array element, and a fixed-ROW destination — fpc accepts the last one, so that is a compat gap and it is why this stays open at a lower prio."
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

## FIXED 2026-09-06 (frankS) — materialised, not refused

Measured at compiler `e9bace5da179`. `compiler/ir.inc`'s `FixedArrayAsArrayCtor`
builds `s[lo] .. s[hi]` as the AN_ARG chain of an `AN_ARRAY_CTOR`, and the
existing ctor lowering does the rest: allocate a dyn temp, SetLength it, store
each element through the NORMAL element-assign path. **That last part is the
reason it is not a block copy** — a byte copy of an `array[0..1] of AnsiString`
would duplicate the handles without retaining them, silently, and no value
assertion would see it.

**The low bound is read from `Syms[].ConstVal`**, which is where `AllocArray`
parks it. `array[1..3]` and `array[0..2]` are both three elements and only the
second is what a zero-assuming index literal would produce.

**fpc refuses a non-zero low bound outright** — `Incompatible types: got
"Array[1..3] Of LongInt" expected "{Dynamic} Array Of LongInt"` — and accepts
`array[0..2]`. We accept both. Us accepting what fpc rejects is not a defect
(CLAUDE.md), and the source plainly means "copy the three elements".

**One call, two doors.** `Insert(t3, t, 2)` with a static source was the same
missing materialisation seen from the parser: it spliced ONE slot holding the
array's address, `4: 1 2 4415304 3` against fpc's `5: 1 2 8 9 3`. The Insert arm
in `pasparser_stmt.inc` now calls the same function rather than growing a second
answer, which needed a FOURTH forward on the parser-into-`ir.inc` seam — every
one of today's four caught by `gate.sh quick`'s FPC seed canary and by nothing
else. **tarray12 is burned** (`Ok`, rc 0, its own eleven CheckArray rows).

### What is left, and why it keeps the ticket open

The element list cannot express three shapes, all now REFUSED by name rather
than left to the bare store:

| shape | fpc | pxx |
| --- | --- | --- |
| multidim source `array[0..1, 0..1]` | (untested) | refused |
| element is itself a dyn array | (untested) | refused |
| destination element is a fixed ROW | **accepts** | refused |

The third is a real compat gap and the only reason this is still open. It is the
same limit `tarray15` records: a row is bytes inside the outer block, not a
handle, so the constructor has nothing to build for it. Dropped to prio 30
because a refusal with a name is not the defect this ticket was filed for.

### The expansion is O(N) nodes

Deliberate, and the same expansion `d := [e0, e1, ...]` already pays. A loop
form would be O(1) code and needs an induction variable synthesised in the IR
lowering. **If a real program assigns a large fixed table this way, that is the
reason to reopen — it is not a correctness question.**
