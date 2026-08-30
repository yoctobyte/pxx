---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Declaring `PRec = ^TRec` and never using it makes `a[0]^` — an expression that mentions neither — print a raw ADDRESS instead of the string. Two programs differing by one unused type line: with it, four deref rows regress; without it, all pass. Pre-existing (`pinned` behaves identically), silent, and action-at-a-distance: it also UNDOES a fix landed in the same file, so a test file that declares such an alias silently reports wrong values for unrelated rows."
status: new
owner: ""
---

# An unused `^TRec` alias changes an unrelated dereference

- **Type:** bug — **Track A**. Silent wrong value, not an error.
- **Found:** 2026-08-30 (frankS) while writing the regression for
  [[refactor-a-two-predicates-answer-what-a-caret-yields]] — the test file
  reported wrong values for rows the fix had just repaired, and the cause was
  the file's own type section.
- **Pre-existing:** `stable_linux_amd64/default/pinned` behaves identically, so
  this is not fallout from that refactor.

## Repro — two programs, one line apart

```pascal
program c6;
{$mode objfpc}{$H+}
type
  PPC  = ^PChar;
  TRow = array[0..1] of PPC;
  TGrid = array[0..1] of TRow;
  TRec = record g: TGrid; end;
  PRec = ^TRec;          { <-- delete this line and the program is correct }
var g: TGrid; q: PPC; s1: PChar;
begin
  s1 := 'alpha'; q := @s1; g[1][0] := q;
  WriteLn('a ', g[1][0]^);
end.
```

| | pxx | fpc 3.2.2 |
| --- | --- | --- |
| as written | `a 4307984` | `a alpha` |
| with the `PRec` line deleted | `a alpha` | `a alpha` |

`PRec` is **never used**. Nothing in the printed expression mentions `TRec`,
`PRec`, or a pointer to a record.

## Why it is worse than one wrong row

In the larger probe the alias's presence regressed **four** rows at once
(`a[0]^`, `a[i]^`, `g[1][0]^`, `g[j][i]^`) — and also re-broke `dy[1][0]^`,
which a fix in the tree had just repaired. So the failure mode is not only "a
wrong value" but **"a wrong value that cancels an unrelated correct one"**, in a
file whose author is measuring something else entirely. It cost a regression
test one full rewrite before the cause was found, and the only reason it was
found is that the same shapes had been measured minutes earlier in a file
without the alias.

## What is measured, and what is not

Measured: presence/absence of the alias line is the discriminator; `pinned`
reproduces; fpc is correct in both. The rows that break are all
`AN_INDEX`-over-`AN_IDENT` derefs whose element is a pointer.

**Not measured — do not take these on trust:** the mechanism. The shape
(declaring one alias perturbs lookups for unrelated pointers) is consistent with
an **alias-table index** being read where a different index is meant —
`AliasElemTk` / `AliasPtrDepth` / `AliasPtrBase*` are indexed by an alias row,
and `ResolveDerefShape` and `NodePtrElem` both read them from `ASTIVal` of an
`AN_PTR_CAST`. But that is a hypothesis from the shape, not a measurement, and
this repo's history says the plausible story is usually dead. Start with
`PXXDBG=a.symptr:*` on both variants and diff — if the symbol metadata for `g`
is identical (it was, for a *different* pair earlier that day: `depth=2
ptrElemTk=17 baseTk=3`), the divergence is downstream of the symbol and the
alias table is the next place to look.

## Gate

`make compiler/pascal26` + both programs above printing `alpha` + the existing
deref tests unchanged (`test_deref_shape_through_arith_and_nonident_base`,
`test_deref_shape_dynarray_and_double`, `test_cast_deref_chain_siblings`,
`test_cast_deref_pointer_field`, `test_cast_lvalue_suffix_siblings`).

**And the real proof: add a `PRec = ^TRec` line to
`test_deref_shape_dynarray_and_double.pas` and watch every row still pass.**
Today that single unused line makes rows `d` and `f` print addresses — which is
how this was found, and it is a sharper assertion than the minimal repro because
it shows the alias cancelling a fix that is otherwise green in the same file.
