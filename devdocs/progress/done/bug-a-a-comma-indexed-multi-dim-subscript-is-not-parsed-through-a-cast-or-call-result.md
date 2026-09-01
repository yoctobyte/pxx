---
slug: bug-a-a-comma-indexed-multi-dim-subscript-is-not-parsed-through-a-cast-or-call-result
title: "`TP(raw)^[i, j]` does not parse, while `p^[i, j]` compiles and runs correctly"
track: A
prio: 45
type: bug
status: done
found: 2026-09-01
found-by: frankB
owner: frankB
blocked-by: []
summary: "FIXED 2026-09-01 (frankB). The cast/deref postfix arm in pasparser_expr.inc read one subscript and then demanded `]`, so `TP(raw)^[i, j]` was a hard parse error in EXPRESSION position while the byte-identical STORE compiled and ran. It now calls ParseNDSubscriptTail -- the fourth caller of the one helper the lvalue side uses, not a fourth copy of the comma walk. The sequencing trap this ticket warned about did NOT fire: frankA landed the multi-dim shape fix first, so the two rows went COMPILE-ERROR -> ok rather than COMPILE-ERROR -> WRONG. test/derefshape is 30/30 with a READ-back-through-the-spelling half added, which is what surfaced this face at all."
---

# A comma-indexed multi-dim subscript is not parsed through a cast or a call result

Found 2026-09-01 while widening `test/derefshape` with a multi-dim pointee axis,
which frankA suggested because `DerefPtrArrayInfo` splits `elemCount` from
`flatCount` for exactly that shape and nothing exercised the split.

## Measured

Pointee `array[0..1, 0..1] of Double`, same loop in every row, at binary
`ffb4dadcf1f8`:

| spelling | result |
| --- | --- |
| `p^[i div 2, i mod 2]` (plain) | **`1.50 6.00` — correct** |
| `r.q^[...]` (record field) | `1.50 0.00` |
| `ap[0]^[...]` (array element) | `1.50 0.00` |
| `pp^^[...]` (nested) | `1.50 0.00` |
| `GetP^[...]` (call result) | **`expected ']' before ','`** |
| `TP(raw)^[...]` (cast) | **`expected ']' before ','`** |

## Why this is not the same bug as the rest of the family

The four value-wrong rows are the pointee-shape family: the base falls off the
array path and lands on whichever arm its element kind collides with. **These
two never get that far.** They fail in the PARSER, on the comma, before any
shape question is asked — so `ProcRetPtrAlias`, `NodePtrAlias` and an
array-element carrier cannot fix them however complete they become.

That is the whole reason for a separate ticket: the shape work legitimately
closes the other rows and will look like it closed the family.

## It is an internal inconsistency, not a compat gap

CLAUDE.md ranks "FPC accepts what we reject" as compat. This is stronger than
that, because **pxx accepts the construct itself** — the plain row above
compiles the same comma-indexed subscript and prints the right answer. The same
expression is accepted or refused according to how the pointer is named.

Oracle checked rather than assumed: FPC 3.2.2 compiles

```pascal
for i := 0 to 3 do TP(raw)^[i div 2, i mod 2] := (i+1)*1.5;
```

and prints `1.50 6.00`, which is also what pxx prints for the plain spelling.

## Repro

`test/derefshape/ds_cast_md2.pas` and `ds_callres_md2.pas`, or:

```pascal
program m;
type TA = array[0..1, 0..1] of Double; TP = ^TA;
var a: TA; raw: Pointer; i: Integer;
begin
  raw := @a;
  for i := 0 to 3 do TP(raw)^[i div 2, i mod 2] := (i+1)*1.5;
  WriteLn(a[0,0]:0:2, ' ', a[1,1]:0:2);     { expect 1.50 6.00 }
end.
```

## Where the missing arm lives

frankA places this in
[[refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend]]
territory, and that ticket is in `done/` — which makes this a **residual of it,
not a duplicate**. Its summary is the reason to expect exactly this defect:

> The pointer/field/index suffix walk is duplicated SIX times in the Pascal
> frontend … Each copy stamps a different subset of the node tags the rest of
> the compiler reads, which is why four separate tickets have now ended "the
> metadata was there, the reader was missing".

A comma-separated index list is one such arm, and the two spellings that refuse
it are two of the copies. So the prediction that ticket makes — that the copies
disagree about which constructs they accept — is confirmed here in the parse
direction rather than the tag direction, which is a face it did not record.

Not reopening a `done/` ticket; noting the link so this is not filed a third
time by someone who greps for "suffix walk".

## Established, same session: the gap IS purely in the subscript parser

The open question above is answered rather than left. **The chained form
compiles for both spellings**, at the same binary:

| spelling | comma form `[i, j]` | chained form `[i][j]` |
| --- | --- | --- |
| `TP(raw)^` (cast) | `expected ']' before ','` | **compiles** → `1.50 0.00` |
| `GetP^` (call result) | `expected ']' before ','` | **compiles** → `1.50 0.00` |

So the defect is in the postfix loop's subscript parser — it does not accept a
comma-separated index list in these two positions — and **not** in the
lowering. That makes it a much smaller job than the rest of the family.

## The sequencing trap this creates, which is the important part

Once parsed, the cast and call-result rows give `1.50 0.00`: **exactly the same
wrong answer as the record-field, array-element and nested rows.** They are not
a separate defect hiding behind the parse error — they are the ordinary
pointee-shape bug, currently *masked* by a compile error.

**So fixing the parser ALONE makes this family worse, not better.** Two loud
compile errors become two silently wrong values, and a silent wrong value is the
failure mode this whole family exists to hunt — the ticket that started it
(`bug-a-p-caret-index-...-plain-identifier`) opens with the record-field face
being the one worth most *because* it is silent.

Do not land the parser fix on its own. Either land it with the multi-dim shape
fix, or land it and accept that `ds_cast_md2` / `ds_callres_md2` move from
`COMPILE-ERROR` to `WRONG` in `test/derefshape` — which is honest only if the
shape work is actually in flight.

## 2026-09-01 (frankB): fixed, and the trap this ticket named did not fire

Landed in the same commit as two other read-face defects. The sequencing warning
above was the right call and was honoured by circumstance rather than by me:
frankA's multi-dim shape fix went in first, so parsing these two spellings turned
them from `COMPILE-ERROR` straight to `ok` — never through the `WRONG` state this
ticket warned it would create.

**How the face was found is the part worth keeping.** Not from this ticket: from
adding a READ half to every `test/derefshape` row. Until 2026-09-01 every row
wrote through the spelling under test and read back through the plain array, so
the matrix was a complete product on the two axes it NAMED and blind on one it
never named. Switching the read half on failed two rows that had been green, and
one of them was this. A matrix's axes are a claim about what was VARIED; they say
nothing about what was COVERED.

The parse fix is three lines of delegation. What made it hard to see for a day
was that the write face — the only face any row exercised — was correct.
