---
slug: bug-p-a-char-array-row-through-a-pointer-deref-loads-short
title: "`s := q^[1]` over a pointer to a 2-D Char array loads three characters where fpc loads six"
track: P
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "The STORE half is correct — `q^[1] := 'XY'` over `^array[0..2, 0..5] of Char` writes `88 89 0 0 0 0` into row 1, byte-identical to fpc. The LOAD half truncates: `s := q^[1]` yields three characters, while `q^[0]` yields all six. The bytes that arrive are the row's own, so the ADDRESS is right and the length is not. Found while adding the AN_INDEX arm to ASTCharArrayCap; that arm EXCLUDES a deref base for exactly this reason, so the deref spelling still refuses rather than answering plausibly-wrong."
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
