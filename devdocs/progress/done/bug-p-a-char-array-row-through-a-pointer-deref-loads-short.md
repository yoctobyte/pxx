---
slug: bug-p-a-char-array-row-through-a-pointer-deref-loads-short
title: "`s := q^[1]` loaded three characters where fpc loads six — the reader was right and the pointee was corrupt"
track: P
prio: 40
type: bug
status: done
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "NOT A LOAD BUG, AND THE TITLE IS THE MISDIAGNOSIS. `s := q^[1]` really did yield three characters where fpc yields six, but the pointee was CORRUPT: `New(q)` sized the block by the pointee's ELEMENT kind, so an 18-byte `^array[0..2, 0..5] of Char` got one byte rounded to sixteen and row 1 held `103 104 32 0 0 0`. Three characters and a #0 is exactly what a reader that stops early looks like. Fixed in ArrTypeByteSize (symtab.inc), both New spellings; the AN_DEREF exclusion in ASTCharArrayCap is removed and the deref base now matches fpc byte for byte. The real defect is filed as bug-p-new-of-a-pointer-to-an-array-type-allocates-the-element-size."
---

# Two rows of the same array, two answers

```pascal
type TG = array[0..2, 0..5] of Char; PG = ^TG;
var q: PG; s: ShortString;
...
s := q^[0];   { six characters — correct }
s := q^[1];   { THREE characters — fpc gives six }
```

Measured with the deref arm temporarily admitted to `ASTCharArrayCap`
(2026-09-05). Ord dump of the store, which is the control:

```
row1: 88 89 0 0 0 0      { q^[1] := 'XY' — pxx and fpc identical }
```

So the row base is right in both directions and the store's capacity is right.

# Why it is not simply "the arm is missing"

At HEAD, with no AN_INDEX arm at all, BOTH rows load ONE character — the index
node's own `ASTTk` is the element kind, so `q^[1]` reads as a single Char. That
is wrong too, and it is the shape
[[bug-p-a-char-array-row-of-a-2d-array-is-not-a-string]] fixed for a variable
and a record-field base.

Admitting the deref base changes `q^[1]` from one wrong character to three
wrong characters. **That is the worse of the two**, because six-vs-one reads as
a missing feature and six-vs-three reads as a working one. The arm therefore
tests `ASTKind[ASTLeft[node]] <> AN_DEREF` and the deref spelling keeps HEAD's
behaviour until the load path is measured.

# Where to look

The count 3 is the OUTER dimension's span, not the inner one, which points at
the dimension table the load path reads for a deref base —
`DerefPtrArrayNDInfo` has two sources (`SymPtrElemNDims` + the pointer symbol's
`SymArrDim*` rows, then the pointee's `ArrType` row) and only one of them is
filled by a Pascal `^TG` declaration. `q^[0]` answering six is consistent with
the row-0 address folding before the wrong span is ever consulted.

Do not fix this by widening `ASTCharArrayCap`; the predicate is answering a
question about an extent, and the extent it would be given is wrong at source.

# RESOLVED 2026-09-05 — the diagnosis in "Where to look" above is WRONG

Keep the section; do not read it as guidance. It said:

> The count 3 is the OUTER dimension's span, not the inner one, which points at
> the dimension table the load path reads for a deref base

**Measured, and it is false in both halves.** Instrumenting `ASTCharArrayCap`
itself printed, for `s := q^[1]`:

```
PXXDBG p.chararraycap base=36 subs=1 ndims=2 span0=3 span1=6 rowCnt=6 tk=3
```

`rowCnt = 6`. The predicate had the right extent all along. `PXXDBG=a.ir:` then
showed the IR for `s := q^[1]` structurally identical to the working
variable-base `s := g[1]`, differing only at node 0 (`load_sym q` vs `lea g`),
which is correct for each; and an address probe gave `@q^[1] - base = 6`, also
correct.

What was wrong was the DATA. A side-by-side dump with identical input:

```
before      : 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114
after q^[0] : 97 98 99 100 101 102 103 104 32 0 0 0 0 0 0 0 0 0
```

`New(q)` allocated the size of a Char. The heap gave 16 bytes, the program wrote
18, and row 1 (bytes 6..11) read `103 104 32 0 0 0` — three characters and a
terminator, which `__pxxCharArrayToStr` correctly stopped at.

# The instrument that lied, and how

**The count 3 was a real number and it was about the heap, not the layout.**
Every reading in the original body was true — the store IS byte-identical to
fpc, `q^[0]` DOES load six, the address IS right — and all of them were taken
on a pointee whose first 16 bytes happened to be intact. The store fit; the
load ran off the end. A defect in the allocator wearing the costume of a defect
in the reader, and the costume fit well enough that the ticket recommended
against the fix that turned out to be correct ("Do not fix this by widening
`ASTCharArrayCap`").

The discriminator was **printing the raw pointee beside fpc's**, which nothing
in the load path would ever have suggested doing. Two rows of one array
disagreeing is a layout question right up until you ask whether the bytes are
even there.

Closed by the same commit as
[[bug-p-new-of-a-pointer-to-an-array-type-allocates-the-element-size]].

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit f09e669ae.
