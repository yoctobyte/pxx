---
prio: 40
track: P
type: bug
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
