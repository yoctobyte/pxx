---
slug: bug-p-sizeof-of-a-variable-is-not-folded-in-a-constant-expression
track: P
prio: 50
type: bug
status: backlog
owner: ""
created: 2026-09-11
found-by: frankS
blocked-by: []
summary: "`array[0..sizeof(d)-1]` where `d` is the enclosing routine's PARAMETER is refused with `unknown type: d` — ConstEvalFactor's sizeof arm resolves a TYPE NAME through ParseTypeKind only, and says so in its own comment. The EXPRESSION path handles a variable and `SizeOf(d)` in a statement answers 8 correctly, so this is one slot missing an arm the compiler already has, not a missing feature. Ten-line repro below. 4 of 207 units of umbrella-pxx-compiles-fpc-itself stop here (entfile.pas:371, and fpcp/pcp behind it); that is a queue position, not a size."
---

# `SizeOf(<a variable>)` is not folded in a constant expression

FPC's `compiler/entfile.pas:371`:

```pascal
function swapendian_entryreal(d:entryreal):entryreal;
type
  entryreal_bytes=array[0..sizeof(d)-1] of byte;
var
  i:0..sizeof(d)-1;
```

`d` is the function's own **parameter**, and both `sizeof(d)` sit in constant
expressions — an array bound and a subrange bound.

```
pascal26:4: error: unknown type: d
  near: array [ 0 .. sizeof ( >>> d ) -
```

## Repro, ten lines, fpc 3.2.2 prints `11`

```pascal
program sz;
type entryreal = double;
function swp(d: entryreal): Integer;
type eb = array[0..sizeof(d)-1] of byte;
var i: 0..sizeof(d)-1; b: eb;
begin
  for i := low(eb) to high(eb) do b[i] := i;
  swp := Length(b) + b[3];
end;
begin WriteLn(swp(1.0)); end.
```

## It is one slot, and the compiler already has the arm

`ConstEvalFactor` (`compiler/pasparser_expr.inc:12392`) documents the gap itself:

> Minimal scope: a type name/keyword resolved via ParseTypeKind -> its byte size
> (covers sizeof(Pointer)/sizeof(Integer)/sizeof(TRec)). A sizeof(variable) or
> sizeof(arr[i]) form is not folded here (rare in a const context; the full
> expression path in ParseFactor handles those).

**"Rare in a const context" is the part the corpus disagrees with** — this is the
idiomatic Pascal spelling of "as many bytes as that value has", and FPC's own
compiler writes it. `SizeOf(d) + SizeOf(g)` in a STATEMENT answers 16 correctly
for two doubles, so the information is present and reachable; only this slot
cannot get at it.

## The shape of the fix, and the trap in it

The narrow version is an arm before `ParseTypeKind`: a bare `tkIdent` that
`FindSym` resolves to a variable or parameter folds to that symbol's storage
size. **Do not try to reuse the expression-level intrinsic wholesale** — it is
~300 lines covering `SizeOf(p^)` of a named fixed array, `SizeOf(expr.field)`,
`SizeOf(TOuter.TInner)`, the `bitsizeof` scale and the `SizeOf(-1)` sign rule,
and it builds an AST node (`EmitSizeOfResult`) where a constant expression needs
an `Int64`. The honest scope is the bare-name form, with `sizeof(arr[i])` and
`sizeof(p^)` left to the expression path exactly as the comment says.

**A positive control that cannot pass by accident:** make the parameter's type
one whose size is NOT 8 and not `SizeOf(Pointer)`. A `double` parameter answering
8 is indistinguishable from a slot nobody wrote, since 8 is also what a bare
pointer-width default would give — see CLAUDE.md on a probe whose right answer
collides with the failure value.

## Where it came from

Attempt 7 of [[umbrella-pxx-compiles-fpc-itself]], probe #12 @ `4c7c88d36`:
4 units stop here. **That is a queue position, not a size** — the same umbrella
measured a 150-unit wall yielding three BOTH-OK units and a 10-unit wall yielding
two. Reduced and left unfiled for one message before being written down here,
which is the only reason this paragraph exists: an unfiled reduction lives in a
peer message and nowhere else.
