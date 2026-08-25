---
slug: bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero
title: "`Length(p^)` over a pointer-to-fixed-array answers 0 where FPC answers the extent"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "`PFixed = ^TFixed` with `TFixed = array[0..3] of LongWord`: `Length(pfx^)` returns 0, fpc 3.2.2 returns 4. Indexing the same deref (`pfx^[2]`) is correct, so the pointer's element metadata IS reachable — Length just does not consult it and falls through to the runtime [data-8] header read on a value that has none. A wrong VALUE, silently, exit 0."
---

# Repro

```pascal
program lp;
type
  TFixed = array[0..3] of LongWord;
  PFixed = ^TFixed;
var fx: TFixed; pfx: PFixed;
begin
  fx[2] := 40;
  pfx := @fx;
  WriteLn(pfx^[2], ' ', Length(pfx^));
end.
```

| | `pfx^[2]` | `Length(pfx^)` |
| --- | --- | --- |
| fpc 3.2.2 `-Mobjfpc -O1` | 40 | **4** |
| pxx, HEAD 2026-08-25 | 40 | **0** |

# Why it is worth more than its size

The index path already knows the pointee is an `array[0..3] of LongWord` — that
is what makes `pfx^[2]` right. So the metadata is present and Length simply does
not ask for it: the deref node is not recognised as array-shaped, Length falls to
the runtime path, reads a length header off a value that has none, and answers 0.
`devdocs/dev/normalise-dont-special-case.md` — the second path is the one that
stays broken.

Suspect the same hole for `Length` of any deref whose pointee is a fixed array
reached other than through a plain variable, and check the sibling questions on
the same node (`High`, `Low`, `SizeOf`) before closing: they read the same
metadata and probably split the same way.

# Where it was found

Writing `test/test_indexing_length_for_new_inc_positive.pas`'s deref row. That
line is deliberately NOT asserted — it carries a comment naming this ticket —
because its neighbours assert the opposite property (that the shape must not be
REFUSED), and asserting today's 0 would freeze the bug.

# Resolution, 2026-08-25 — the ticket named the symptom, the cause was worse

`Length(p^)` answering 0 was the visible end of it. Varying the shape found the
real defect one level down, and it was a **silent wrong value**:

```pascal
type TW = array[0..3] of Int64; PW = ^TW;
...  for i := 0 to 3 do w[i] := 100 + i;  qw := @w;
     WriteLn(qw^[0], ' ', qw^[2], ' ', qw^[3]);
```

| | fpc 3.2.2 | pxx (before) |
| --- | --- | --- |
| `qw^[0] qw^[2] qw^[3]` | `100 102 103` | **`100 101 0`** |
| `qra^[1].b` (array of records) | `11` | **`1`** — the FIRST field |
| `SizeOf(qw^)` | 32 | **8** — one element |

The ticket's own reading — "the index path already knows the pointee is an
`array[0..3] of LongWord`, so the metadata IS reachable" — was wrong, and wrong
in the way `devdocs/dev/root-cause-over-microfix.md` warns about: `pfx^[2]` was
right by ACCIDENT, because a LongWord and the tyInteger the compiler had
actually recorded are both 4 bytes wide. Change the element to an Int64 or a
record and the same expression reads the wrong bytes.

## Cause

A named ARRAY type is not in the scalar alias table, so `ParseTypeKind` on the
pointee falls through its unknown-name default and answers `tyInteger`. Both
spellings of the pointer did this:

- `^TFixed` inline, in ParseTypeKind's `tkCaret` arm;
- `PFixed = ^TFixed`, in ParseTypeSection's pointer-alias arm.

So `PtrElemTk` was `tyInteger` (stride 4) and `PtrElemRec` `REC_NONE` for every
pointer to an array in the language. Three other paths in this compiler already
knew to take the element shape from the `ArrType` entry instead — the
function-result path, the record-field path, the var-of-alias path — each having
learned it from its own bug. This was the fourth spelling and the one nobody had
added.

## Fix

1. Both pointer-parse sites detect a non-dynamic array alias and take
   `elemTk`/`elemRec` from `ArrTypeElemTk`/`ArrTypeElemRec`, keeping the alias
   index in the new `LastTypePointerElemArrAi` / `AliasPtrElemArrAi`.
2. `Alloc*` records the pointee's extent in **`SymPtrElemArrLen`** — the slot the
   C frontend already used for `elem (*p)[N]`, whose comment describes exactly
   this concept — with the low bound and per-dim spans in the pointer symbol's
   otherwise-unused `SymArrDim*` rows. No new parallel array: one concept, one
   slot, shared by both frontends.
3. One reader, `DerefPtrArrayInfo` (symtab.inc), so `Length` / `High` / `Low` /
   `SizeOf` / the index path all ask the same question instead of four
   near-copies.
4. `ResolveNodeRec`'s `AN_INDEX` branch gained its missing `AN_DEREF` arm —
   literally the omission the `AN_CALL` arm two lines below already documents
   (`bug-a-indexing-a-function-call-result-drops-the-field-selector`): with no
   arm the element record was `REC_NONE`, so `p^[i].b` resolved every field at
   offset 0.
5. The index path normalises a non-zero LOW BOUND where the bound is known
   (`array[1..4]` indexed from the base and ran one element past the end).

## Measured

`test/test_pointer_to_a_named_fixed_array.pas` — Int64 elements, LongWord
elements, a non-zero low bound, an array of records (per-field reads, whole
element copy, and a write THROUGH the pointer), each with
`Length`/`Low`/`High`/`SizeOf`. Diffs MATCH against fpc 3.2.2; `.expected` IS
fpc's own output. Wired into `test-core`.

fpc-testsuite, same command before and after: **345 pass, 1 fail, 170 skip** —
no movement. `make compiler/pascal26` fixedpoint converged in one round at every
step; `tools/gate.sh quick` GREEN.

`PXXDBG=a.symptr` now prints `ptrElemArrLen` and `ptrElemNDims` — the two fields
that would have answered this ticket's root-cause question in one command.

## Left open, deliberately, with the test naming each

- `bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent` —
  `qg^[i, j]` flattens with the wrong dims and `Length` answers the flat extent.
  Predates this fix (verified against the pre-fix binary: identical output); the
  metadata it needs is now present.
- `bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one` — the pointee is a
  handle, so the header is one indirection further than the runtime path looks.
- A FORWARD `PA = ^TA` ahead of `TA`'s declaration cannot see an `ArrType` entry
  that does not exist yet, and keeps the old behaviour.

## Log
- 2026-08-25 — resolved, commit 99939b3a1.
