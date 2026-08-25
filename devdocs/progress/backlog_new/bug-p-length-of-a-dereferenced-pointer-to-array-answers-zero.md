---
slug: bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero
title: "`Length(p^)` over a pointer-to-fixed-array answers 0 where FPC answers the extent"
track: P
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
