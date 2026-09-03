---
prio: 40
track: P
type: bug
status: done
---

# `r.v[0]` on a field of type `array of array of T` types as T, not `array of T`

One index into a nested dynamic-array FIELD yields the LEAF type instead of the
inner array. The same expression on a LOCAL is correct, so this is a
field/local asymmetry, not a missing feature.

## Repro

```pascal
type TR = record v: array of array of AnsiString; end;
var r: TR;
begin
  SetLength(r.v, 1); SetLength(r.v[0], 1);
  r.v[0][0] := 'ab';    { error: cannot assign ShortString to Char }
end.
```

`r.v[0]` is typed AnsiString, so the second `[0]` is a CHARACTER index. The
identical code with `v` as a local variable compiles and runs correctly:

```pascal
var v: array of array of AnsiString;   { v[0][0] := 'ok' works }
```

## What works, which bounds the damage

Assigning the inner array out to a local and indexing THAT is correct, and
releases correctly (1500 trips: allocs=5411 frees=5408 live=3):

```pascal
inner := r.v[0];   { correctly typed array of AnsiString }
inner[0] := 'w';
```

So the storage, the descriptor and the element walk are all fine — only the
type the parser assigns to the intermediate index expression is wrong. That
also means there is a working spelling for anyone who hits this.

## Why it was worth measuring twice

Found while sweeping managed-element leaks. The first read was that
`2b70ff387` had introduced a SIGSEGV here, because the same program exits 0 on
that commit's parent and segfaults after it. It had not: before `2b70ff387` an
`array of AnsiString` field was misdescribed as a plain String member, so the
program leaked instead of crashing. The crash needs the ill-typed write above
to be ACCEPTED first, which was a separate hole
([[bug-p-a-string-concat-assigned-to-a-char-lvalue-is-not-type-checked]], fixed
since). Well-typed nested-field code is clean on the current compiler, measured.

Recording that because "my change broke it" was the obvious reading and was
wrong: the change only converted a silent leak into a loud crash in a program
that should never have compiled.

## Where to look

`UFldDynDepth` is recorded correctly (`array of array of T` gives 2 — the parse
loop in `pasparser_decl.inc` counts the nested `array of`s), and `UFldTk` is
the LEAF type by design. So the depth is available and the indexing path is
simply not consuming it: one index into a depth-2 field must yield a depth-1
array, not the leaf. The local path already does this, and is the oracle.

## Fixed by `45391912a`, measured 2026-09-03 (frankA)

Same defect, one element class over. `45391912a` closed
[[bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char]] — a field
of `array of array of string[10]` indexing as a Char — by deleting the second
dyn-depth walker: `symtab.inc`'s `DynArrayNodeDepth` had no `AN_FIELD` arm, so
`IsNodeArray` got depth 0 for `r.v` and the selector chain took the
index-a-STRING branch. That is exactly the mechanism this ticket's "Where to
look" predicted — the depth is recorded and was not consumed — and the walker is
element-type-blind, so the AnsiString spelling here went with it.

Positive control, both modes, on the ticket's own repro plus a
type-discriminating row (`Two(r.v[0])` where `Two` takes `array of AnsiString`,
which cannot typecheck if `r.v[0]` is the leaf):

| compiler | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| pin v401 `766b99f98` (ancestor of the fix) | `error: cannot assign ShortString to Char` | same error |
| HEAD `7ee75c8e1` | `INNER <ab><cd>` `PARAM <ab/cd>` `CHAR <a>` | identical |

The pinned arm reproduces the ticket's error string verbatim, so this is a real
fix and not a mis-filed repro. `r.v[0][0][1]` still indexes a CHARACTER at depth
3, so consuming the depth did not cost the leaf its string indexing.

Regression cover already exists and needs nothing added:
`test/test_field_rooted_nested_dyn_frozen_index.pas` carries the `ANSI` row
(`ra: record m: array of array of AnsiString`) beside the `string[10]` and
`Integer` ones, asserting VALUES rather than lengths.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 49ce033d0.
