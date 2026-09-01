---
slug: bug-a-a-comma-indexed-multi-dim-subscript-is-not-parsed-through-a-cast-or-call-result
title: "`TP(raw)^[i, j]` does not parse, while `p^[i, j]` compiles and runs correctly"
track: A
prio: 45
type: bug
status: new
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
summary: "A comma-indexed multi-dim subscript is refused with `expected ']' before ','` when the pointer is spelled as a CAST or a CALL RESULT, while the identical construct on a plain identifier compiles and produces the right answer. So pxx disagrees with ITSELF by spelling, which is stronger than a compat gap; FPC 3.2.2 accepts the cast spelling and prints the same values pxx prints for the plain one. Same family as bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier, but a DIFFERENT MECHANISM and not fixed by it: this fails during PARSING, before any pointee-shape machinery runs, so no carrier (ProcRetPtrAlias, NodePtrAlias, an array-element carrier) can repair it. Filed separately so it is not assumed covered by the shape fix. Rows ds_callres_md2 and ds_cast_md2 in test/derefshape. ESTABLISHED same session: the CHAINED form `[i][j]` COMPILES for both spellings and yields 1.50 0.00, the same wrong answer as the record-field/array-element/nested rows -- so the gap is purely the postfix subscript parser and behind it sits the ordinary shape bug, currently MASKED by the parse error. Fixing the parser alone therefore turns two LOUD compile errors into two SILENT wrong values; land it with the multi-dim shape fix, not before."
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
