---
slug: bug-a-a-typed-procvar-constant-cannot-be-called
track: A
prio: 40
status: done
commit: 03d1ab08b
---

# A typed procvar constant can be declared and assigned, but never called

```pascal
type TFn = function(x: Integer): Integer;
function Sq(x: Integer): Integer; begin Result := x*x; end;
const K: TFn = @Sq;
begin WriteLn(K(7)); end.
```

```
pascal26:4: error: unexpected token
```

fpc 3.2.2 prints `49`. The declaration itself was fine, and so was every
*indirect* use:

| form | before |
| --- | --- |
| `const K: TFn = @Sq;` | ok |
| `f := K; f(7)` | ok |
| `Assigned(K)` | ok |
| `Use(K)` (procvar argument) | ok |
| **`K(7)`** | **syntax error** |

So the value was right and only the call syntax was missing — which is why it
survived: any code that routes through a variable works, and that is how most
code uses a procvar table.

## Cause

Both call sites gate on the symbol carrying a signature:

```pascal
{ pasparser_stmt.inc:4636 — statement position }
if (si >= 0) and (SymProcSig[si] >= 0) and (Tokens[TokPos].Kind = tkLParen) then
  node := ParseProcVarCallAST(si, SymProcSig[si])
{ pasparser_lval.inc:70 — expression position, same test }
```

`ParseTypeKind` resolves `TFn` to `tyPointer` and publishes the signature in
`LastTypeProcSig`. The **var** declaration path copies it
(`pasparser_decl.inc:886`, `SymProcSig[idx] := LastTypeProcSig`). The **typed
const** path allocates its symbol a few hundred lines further down and copies
`PtrElemTk` and `PtrElemRec` from the same set of `LastType*` globals — but not
`LastTypeProcSig`. `SymProcSig` stayed at its `-1` default from `AllocVar`, both
gates read false, and the parser fell through to "identifier, then an
unexpected `(`".

The same double-case as `bug-a-a-label-section-must-come-last-in-a-routine`
earlier today, one level down: two places construct a symbol from one set of
`LastType*` globals, one of them forgets a field, and the arm that forgets is
the rarer one. `devdocs/dev/normalise-dont-special-case.md`. The real cure is
`feature-a-typeref-migrate-consumers` — a single `SymSyncTypeRef`-shaped
publish instead of N hand-copied parallel arrays — and this is one more
datapoint for it. Both arms already call `SymSyncTypeRef` immediately after,
so the copies sit *directly beside* the thing meant to replace them.

## Fix

One line, mirroring the var arm:

```pascal
SymProcSig[cIdx] := LastTypeProcSig;
```

in `pasparser_decl.inc`'s typed-const `tyPointer` branch, before the existing
`SymSyncTypeRef(cIdx)`.

Not widened to the `of object` form: a method pointer is a `tyRecord` alias and
takes the record-typed-const branch, but a method pointer needs an *instance*,
so there is no constant expression to initialize one with at all — the shape is
not expressible, not merely unsupported.

## Verification

- `test/test_typed_procvar_const_is_callable.pas`, wired into `test-core`:
  direct call, proc-typed const, parameterless with and without parens,
  routine-local const (a different storage path — static BSS plus a prologue
  init, not a `.data` global), via-var, a const call inside a larger expression,
  and a const passed as a procvar argument. Byte-identical to fpc 3.2.2.
- The 27-program procvar differential this came from: 26/26 valid rows match.
  (The 27th, `@TC.Handle`, is rejected by FPC without a cast; pxx accepts it,
  which is the dialect's documented laxness, and the row's body was a no-op.)
- `make compiler/pascal26` self-host fixedpoint, converged in 1 round.
- `tools/gate.sh quick` green.

## Note on the conformance suite

`library_candidates/fpc-testsuite/.../tprocvar1.pp` is skipped with the reason
"gap: method pointers (`procedure(l:longint) of object`), @Class.Method,
typed-const procvars". The first of those three is **stale** — method pointers
work fully today (assignment from an instance method, virtual dispatch through
one, comparison, storage in arrays/records/dynarrays, `TMethod` punning, and
`@Self.Virt` from inside a method all verified against FPC). The third is what
this ticket fixed. Only `@Class.Method` remains, and FPC itself rejects the bare
form. Worth re-checking whether the test now passes; the skip reason should
shrink either way.
