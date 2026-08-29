---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`&a.m[1][0] - &a.m[0][0]` on a struct field `int m[3][4]` answers 1 where gcc says 4. IRArrayElemStride exists precisely so a FULLY indexed base gets the ELEMENT stride instead of the row stride, and its own comment names 1 as the wrong answer — but it has only an AN_IDENT arm, so an AN_FIELD base falls through to IRPointerStride and gets exactly the row stride the split was made to avoid."
status: done
owner: frankC
---

# IRArrayElemStride has no AN_FIELD arm, so a field base gets the ROW stride

- **Type:** bug (silent wrong value) — **Track A file** (`compiler/ir.inc`),
  found from Track C.
- **Found:** 2026-08-30 (frankC), during
  [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]]. It is
  the sixth site of that ticket's shape and the only one in A's file, so it is
  filed rather than fixed: `ir.inc` is released to frankA.

## Measured (gcc oracle)

```c
struct S { int m[3][4]; } a;
int gm[3][4];
```

| expression | gcc | pxx |
| --- | --- | --- |
| `&gm[1][0] - &gm[0][0]` | 4 | 4 |
| `&a.m[1][0] - &a.m[0][0]` | 4 | **1** |

Every other ptrdiff spelling over a field now agrees with gcc (`a.m[1]-a.m[0]`,
`(a.m+1)-(a.m+0)`, `a.s[2]-a.s[0]`); this is the last cell.

## Cause — and the comment that already predicted it

`IRPointerStride`'s AN_ADDR arm routes `&arr[i]` through `IRArrayElemStride`
rather than asking for the plain stride, and says why, in the source:

> *the ELEMENT, deliberately: `&g[1][0] - &g[0][0]` on `char g[2][8]` is 8
> elements, and asking the plain stride would answer the ROW stride the
> multi-dim decay arm above returns — 8 — **making that difference 1**.*

`IRArrayElemStride` then tests `ASTKind[node] = AN_IDENT` and, for anything
else, falls back to `IRPointerStride(node)` — which for an AN_FIELD base hits
the (correct, recently fixed) row-decay arm and returns `RecFieldRowStride` =
16. 16 bytes apart / 16 = **1**: the precise number the comment names as the
symptom of asking the wrong function.

So this is not a new failure mode. It is the documented one, reached through
the spelling the guard does not cover — the same AN_IDENT-arm-only shape as
[[bug-c-a-multidim-array-field-decays-with-the-element-stride]],
[[bug-c-a-struct-field-partial-index-uses-the-outer-row-stride]] and
[[bug-c-sizeof-a-partial-index-answers-the-element-not-the-row]].

## Fix

Give `IRArrayElemStride` the AN_FIELD arm its AN_IDENT arm has. It cannot use
Track C's `CNodeArrayShape` (that lives in `cparser.inc` and requires rank >= 2,
while this wants rank 1 too), so it is the plain pair:

```pascal
if (node >= 0) and (ASTKind[node] = AN_FIELD) then
begin
  recId := ResolveNodeRec(ASTLeft[node]);
  fname := GetASTIdentName(node);
  if RecFieldIsArray(recId, fname) and (RecFieldDynDepth(recId, fname) = 0) then
  begin
    etk := RecFieldType(recId, fname);
    if etk = tyRecord then Result := RecSize(RecFieldRecId(recId, fname))
    else if etk = tyUnknown then Result := 1
    else Result := TypeSize(etk);
    Exit;
  end;
end;
```

Untested — written from the diagnosis, not compiled, because the file is not
mine to build against right now. Treat it as a starting point, not a patch.

## Gate

`make compiler/pascal26` + a repro asserting both rows of the table above.
`test/cderef_decay_through_a_field.c` is the natural home for it; its last two
assertions are already the `*(a.m+1) - *(a.m+0)` pair.

## RESOLVED — 2026-08-30 (frankC)

Fixed as filed: `IRArrayElemStride` gains the AN_FIELD arm its AN_IDENT arm
has. The patch sketch above was written before the file was mine and is
labelled untested; what landed is the same shape with the `tyUnknown` guard
its sibling arm carries.

`ir.inc` was released by frankA (grant `7cbd854d2`); no other lane held it.

**This closes the array-shape census: 33 wrong cells -> 4 -> 0.** All six
spellings now agree with gcc on all 21 constructs.

### Evidence

- `&a.m[1][0] - &a.m[0][0]` = 4, and the `char`/`double`/3-D forms with it
  (16, 3, 12) — three element widths, because a wrong stride can coincide with
  the right answer at one width.
- Differential over **37 named C tests: all 37 byte-identical.** Expected, and
  itself the finding: nothing in the corpus reaches `&field[i][j]` arithmetic,
  so the eight assertions added to `test/cderef_decay_through_a_field.c` are
  its only coverage. gcc 42 / `pinned` SIGSEGV / fixed 42.
- Self-host fixedpoint `7c4f7ce26297`.
- `tools/gate.sh quick` **GREEN** — run because this is a shared A file, and it
  caught a real defect in the *previous* commit (below).

### The gate caught something the fixedpoint structurally cannot

`gate.sh quick` went RED on the FPC seed, not on this change but on
`392782317` two commits earlier: `CNodeArrayShape` is called ~1000 lines above
its body, pxx prescans the unit and FPC resolves in source order, so the seed
could not compile while `make compiler/pascal26` stayed green through it.

That is the hole CLAUDE.md documents, arriving in the ordinary way: the
fixedpoint proves the compiler reproduces **itself**, and a missing `forward;`
does not disturb that. Fixed in `f877923cb`, inert to codegen (same fixedpoint
sha). Worth recording as the concrete argument for the "when you touched
something you're nervous about" clause — a new routine called from a distant
include is that, and I ran the gate one commit late.

## Log
- 2026-08-30 — filed by frankC from the last census cell, with the diagnosis.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
