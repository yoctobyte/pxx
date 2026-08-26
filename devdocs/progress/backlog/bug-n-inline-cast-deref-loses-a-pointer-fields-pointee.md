---
track: N
prio: 55
type: bug
blocked-by: []
summary: "compiler/pyparser.inc:44098 carries a byte-identical copy of the alias-cast postfix loop just fixed on the Pascal side: its `^` arm answers the pointee from the ORIGINAL cast's alias every time, so the second `^` in a `PRec(x)^.fld^` chain gets the type the CAST points at instead of the type the FIELD points at. The deref happens, only the tag is wrong, so the value is plausible and silently wrong."
status: backlog
owner: unassigned
---

# N an inline cast's `^` chain answers every deref from the cast's alias

- **Track N** (`compiler/pyparser.inc`, ~line 44092).
- Sibling of [[bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped]],
  fixed on the Pascal side. Filed rather than edited: `pyparser.inc` is Track
  N's file and N work is deferred, so this is a hand-off, not a half-applied
  change.

## The code, verbatim, in both files

```pascal
if CurTok.Kind = tkCaret then
begin
  Next;
  indexNode := AllocNode(AN_DEREF);
  ASTLeft[indexNode] := node;
  { After ^, type becomes the pointee }
  tk      := IntToTypeKind(AliasElemTk[aliasIdx]);
  recName := AliasElemRec[aliasIdx];
  ASTTk[indexNode] := StrValTk(tk);
  node := indexNode;
end
```

`aliasIdx` is the alias of the cast that OPENED the chain and never changes, so
every `^` in the chain is answered from it. By the second `^` in
`PRec(raw)^.n^` the node is the field `n`, not the cast — and `n`'s pointee is
not `PRec`'s.

## Why it is worth fixing even though the bytes are right

The deref is applied; only the resulting TYPE TAG is wrong. On the Pascal side
that meant `Writeln` printed a string's heap address as an integer, while the
same chain with the cast parked in a variable printed the string — two spellings
of one expression disagreeing, with no diagnostic. A `^Int64` field through the
same cast looked fine because the wrong tag happened to match. That is this
repo's expensive failure mode, not a crash.

## Fix — take the Pascal one, do not write a new one

The Pascal fix was deliberately NOT made at the call site. It extended the
shared `NodePtrElem` predicate (`compiler/pasparser_lval.inc`) with the two
spellings it did not know — a pointer FIELD (`UFldPtrElem*` via
`ResolveNodeRec`) and an inline `AN_PTR_CAST` (the alias, guarding the negative
adapter markers) — and the caret arm then asks the predicate about the CURRENT
node, falling back to `aliasIdx` only when it has no answer (which is what the
-1/-2 adapter casts need). `NodePtrElem` is shared, so N gets the predicate for
free and only the caret arm needs changing.

Copy `test/test_cast_deref_pointer_field.pas` and
`test/test_cast_deref_chain_siblings.pas` into the `.npy` suite in whatever
spelling NilPy reaches this path with. **First establish that NilPy can reach
it at all** — if no NilPy program can express the chain, this is dead code in
that file and the right outcome is deleting it, not porting a fix into it.

## Gate

`make test-nilpy` green + self-host byte-identical, per Track N's lane rules.
