---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Declaring `PRec = ^TRec` and never using it makes `a[0]^` — an expression that mentions neither — print a raw ADDRESS instead of the string. Two programs differing by one unused type line: with it, four deref rows regress; without it, all pass. Pre-existing (`pinned` behaves identically), silent, and action-at-a-distance: it also UNDOES a fix landed in the same file, so a test file that declares such an alias silently reports wrong values for unrelated rows."
status: done
owner: frankA
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

---

# Resolution — the named array type never recorded the pointee's DEPTH or BASE

**Done, 2026-08-30 by frankA.** Fixedpoint `3d23868b1ded` (1 round),
`tools/gate.sh quick` GREEN.

## The hypothesis in the ticket was right in family and wrong in place

The ticket guessed an **alias-table index** read where a different index was
meant. It is not the alias table. `PXXDBG=a.symptr:*` on both variants — the
first thing the ticket says to do — diffs to exactly **one line**, and the
divergence is upstream of every deref walk, in the symbol itself:

```
with the alias     g kind=17 isArray=TRUE elemType=17 depth=0 ptrElemTk=17 baseTk=0
without it         g kind=17 isArray=TRUE elemType=17 depth=2 ptrElemTk=17 baseTk=3
```

`ptrElemTk` is right in both. **`depth` and `baseTk` are what the alias line
destroys.**

## Vary the shape, and the ticket's own title stops being true

| extra type line | result |
| --- | --- |
| *(none)* | `alpha` |
| `TRec = record g: TGrid; end;` alone | `alpha` |
| `TRec` + `PRec = ^TRec` | **address** |
| `PInt = ^Integer;` | **address** |
| `PGrid = ^TGrid;` | `alpha` |
| `PRow = ^TRow;` | `alpha` |

So it is **not about records** — `^Integer` does it just as well — and it is not
about the field name (renaming the record's `g`, and renaming the variable,
changed nothing; that killed the name-collision hypothesis in one build). The
discriminator is *any* pointer alias whose pointee is **not an array**, declared
after the array type.

## Mechanism, measured

`defs.inc` carries a **pointee carrier set** on each named array type's row:
`ArrTypePtrElemRec`, `ArrTypePtrElemTk`, `ArrTypePtrElemStrTk`. It exists
because a *use* of a named array type is arbitrarily far from where that type
was parsed, and by then the `LastTypePointer*` return channel describes whatever
pointer declaration the unit parsed last.

**The set was missing its last two members**: `LastTypePointerDepth` and
`LastTypePointerBaseTk`/`BaseRec` were never stored on the row, so
`AllocArray`'s symbol write (`symtab.inc:4291-4293`) read them straight from the
stale globals. With only `PPC = ^PChar` declared they still held PChar's values
and the answer was **accidentally right**. `PInt = ^Integer` overwrites them and
the accident stops. `PGrid = ^TGrid` does not, because an array pointee leaves
the depth/base pair alone.

This is the **fourth** column of one carrier set to be found missing, and
`defs.inc` documents the previous three in place — each added one ticket at a
time, each needing ~19 restore sites updated by hand. `ArrTypeAliasOf`'s own
comment predicts exactly this: *"a clone enumerates a field list that goes stale
the day a 23rd column is added."*

## Fix — one reader and one writer, not three more columns at nineteen sites

- `defs.inc`: `ArrTypePtrDepth`, `ArrTypePtrBaseTk`, `ArrTypePtrBaseRec`.
- `symtab.inc`: `LoadPointeeFromArrType(ai)` / `StorePointeeToArrType(row)` —
  now the **only** reader and writer of the whole set.
- The 18 identical three-line restore blocks and the 2 store blocks across
  `pasparser_decl.inc` / `_lval.inc` / `_proc.inc` collapse into one call each
  (**60 lines deleted, 26 added** in those three files). A seventh column now
  costs two lines and no sweep.
- One site restores into **locals** (`retPtr*`, `pasparser_proc.inc:1048`) and
  so cannot use the helper; it was carrying three of six and now carries six.
  That is a second live instance of the same drop, found only because the sweep
  enumerated every access rather than every *call*.

## Evidence

Nine variants above: all print `alpha`. The pinned binary prints an address for
three of them.

**The proof the ticket asked for is now permanent.** `PRec = ^TRec` is added to
`test/test_deref_shape_dynarray_and_double.pas` — unused, with a comment saying
why it must stay — and every row still matches `.expected`. **On `pinned` that
same file now fails rows `d`, `e` and `f`**, so the test has a control that goes
red, which is the whole reason to put the alias in a file that was already green
rather than to write a new minimal repro.

Unchanged against `pinned`: `test_deref_shape_through_arith_and_nonident_base`,
`test_cast_deref_chain_siblings`, `test_cast_deref_pointer_field`,
`test_cast_lvalue_suffix_siblings`,
`test_pointer_to_a_pointer_through_a_cast_and_a_forward`,
`test_ptr_depth2_bases`, `test_pointer_deref_depth` (exit 42, empty output, on
both binaries — pre-existing and identical).

## Log
- 2026-08-30 — resolved, commit 6f894db66.
