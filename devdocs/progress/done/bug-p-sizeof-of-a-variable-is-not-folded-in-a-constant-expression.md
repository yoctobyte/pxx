---
slug: bug-p-sizeof-of-a-variable-is-not-folded-in-a-constant-expression
track: P
prio: 50
type: bug
status: done
owner: frankH
created: 2026-09-11
found-by: frankS
blocked-by: []
summary: "FIXED. `array[0..sizeof(d)-1]` where `d` is the enclosing routine's PARAMETER was refused with `unknown type: d` — ConstEvalFactor's sizeof arm resolved a TYPE NAME through ParseTypeKind only. `TryConstSizeOfSymbol` adds a symbol-first arm, asked before the type arm because TSymKind has no type kind and a type name therefore cannot reach FindSym. Deliberately narrow: it DECLINES skConst, an IsArray symbol, tyUnknown and a frozen string rather than answer from fields TSymbol does not have, and a declined shape still refuses loudly. Seven shapes measured against fpc 3.2.2, all agreeing; the record control is 3 bytes and the ordinal a Word, because 8 is also what an unwritten slot answers. Test test_sizeof_of_a_variable_in_a_const_expr.pas in test-core asserts no pointer width, so it is target-independent. The 4 fpc units that stopped here now stop ELSEWHERE — that is not a claim they compile."
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

## Resolved — the narrow arm, measured against fpc 3.2.2

`TryConstSizeOfSymbol` in `compiler/pasparser_expr.inc`, immediately before
`ConstEvalFactor`, plus a symbol-first arm in the sizeof slot. The arm is asked
**before** the type arm, which costs nothing: `TSymKind` has no type kind
(`symtab.inc:5792`), so a type name cannot resolve through `FindSym` at all and
the two populations do not overlap.

It DECLINES four shapes rather than guessing, because `TSymbol` does not carry
what the answer would need: `skConst`, an `IsArray` symbol (no dimension list),
`tyUnknown`, and a frozen string (`TypeIsFrozenString` — no capacity field, so
`string[10]` would confidently answer the 8-byte handle where fpc says 11).
A declined shape still says `unknown type: <name>`, i.e. **no silent wrong
number**; `sizeof(arr[i])` and `sizeof(p^)` stay with the expression path,
exactly as the arm's own comment always said.

Every row below is pxx against fpc 3.2.2 on the same source:

| shape | pxx | fpc |
| --- | --- | --- |
| the ticket's repro (`double` param, array + subrange bound) | 11 | 11 |
| 3-byte record param — a size no default can produce | 3 | 3 |
| `var r: TThree` — IsRef set, still the DECLARED type | 3 | 3 |
| `Word` param through a local `const` | 2 | 2 |
| `sizeof(Pointer) sizeof(Integer) sizeof(TR)`, bound, default param | 8 4 16 16 8 | 8 4 16 16 8 |
| `var d: string[10]` | refused | n/a — declined on purpose |
| `var d: array[0..2] of Integer` | refused | n/a — declined on purpose |

The last regression row needed `{$mode objfpc}` before fpc would take it at all
— a default parameter value is not ISO Pascal — so the first oracle run failed
to compile and said nothing about pxx. **Worth recording because the numbers in
that row are 8, 4 and a pointer width**, which is the collision CLAUDE.md warns
about, and for an hour they were pxx's answers with no oracle beside them.

Test: `test/test_sizeof_of_a_variable_in_a_const_expr.pas`, wired into
`test-core`. It asserts 3, 3, 2 and 11 and **no pointer width**, so it is
target-independent. Positive control run by stashing the fix and rebuilding: the
pre-fix binary (a different sha, `b1f2e97bf9a8`) refuses the fixture at line 21
with the ticket's own message.

What this does NOT claim: the four units of
[[umbrella-pxx-compiles-fpc-itself]] that stopped here now stop somewhere else,
not that they compile. A first-failure census reports one wall per subject.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
