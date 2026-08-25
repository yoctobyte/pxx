---
slug: bug-p-a-nested-dynamic-array-result-crashes-however-it-is-reached
title: "A function returning `array of array of T` segfaults on the first index, even through a variable"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "`m := MakeMat; WriteLn(m[1][0])` where MakeMat returns `array of array of Integer` SEGFAULTS — on the pinned compiler and on HEAD. Nothing to do with indexing the call result directly: the value is already wrong by the time it reaches a variable, so the nesting is lost somewhere between the callee's Result and the caller's slot."
---

# Measured, 2026-08-25 (pinned AND HEAD — identical)

```pascal
type TIntArr = array of Integer;
     TMat    = array of array of Integer;   { the named-alias spelling behaves the same }
function MakeMat: TMat;
var r0, r1: TIntArr;
begin
  SetLength(r0, 2); SetLength(r1, 2);
  r0[0] := 1; r0[1] := 2; r1[0] := 3; r1[1] := 4;
  SetLength(Result, 2); Result[0] := r0; Result[1] := r1;
end;
var m: TMat;
begin
  m := MakeMat;
  WriteLn(m[1][0], ' ', Length(m), ' ', Length(m[1]));   { fpc: 3 2 2 }
end.
```

pxx prints the leading literal and then **SIGSEGV**. `Length(MakeMat[1])` dies
the same way. The one-level case (`array of Integer` returned and indexed) is
correct in every spelling — see
[[compat-pascal-index-a-function-call-result]] and
`test/test_index_a_dynamic_array_call_result.pas`.

# Why it is filed separately

It was hit while landing the call-result indexing fix, and the first suspicion
was that fix. It is not: **the via-VARIABLE spelling crashes identically on the
PINNED binary**, so the defect is older and lives below the indexing question —
somewhere in how a nested dyn-array RESULT is built, returned or stored, not in
how it is subscripted.

A related smell found in passing, worth checking first: `SetLength(Result[0], 2)`
— sizing the inner array through `Result` — is refused outright with *"SetLength
expects an array variable in IR codegen"*, which is why the repro above has to
build `r0`/`r1` as locals and assign them in. Both point at `Result` of a nested
dyn-array type not carrying its full shape.

# Suspected, NOT measured

`ProcRetDynDepth` is the obvious suspect (`ArrTypeDynDepth` for the alias arm,
the hardcoded `retDynDepth := 1` for the literal `array of` arm in
`compiler/pasparser_proc.inc` ~944). But the via-variable crash means the value
itself is wrong, so check what the CALLEE writes before blaming what the caller
reads — `PXXDBG=a.symptr:*` on Result, then the IR of the return.

# Gate

`make compiler/pascal26` + the repro above matching `fpc -O1` + `tools/gate.sh
quick`. Add the two-level rows to
`test/test_index_a_dynamic_array_call_result.pas`, which deliberately omits them
today.


## RESOLVED 2026-08-25 — one hardcoded `1`, and two consumers keyed on a spelling

**Root cause, measured not guessed.** `compiler/pasparser_proc.inc` allocated the
Result slot as

```pascal
idx := AllocDynArray('Result', retElemTk, 1);
```

— a hardcoded nesting of 1, while `ProcRetDynDepth[procIdx]` two hundred lines
above already held the declared one. So for `function F: TMat` an OUTER element
was read as a 4-byte Integer instead of an 8-byte handle. Nothing else about
the value was wrong, and the bisect below is what said so:

| spelling | before |
| --- | --- |
| `loc: TMat` local inside the function | **correct** (2 2 3) |
| `procedure Fill(var Res: TMat)` | **correct** |
| `Result := loc` then read `Result[1]` | garbage |
| `Result[1] := r1` then read in the CALLER | `Length(m[1])` = 0 |
| `SetLength(Result[0], 2)` | refused: *"SetLength expects an array variable"* |

The ticket's own suspicion (`ProcRetDynDepth`, `retDynDepth := 1`) was aimed at
the right family and the wrong line: the proc ROW was right all along — the
alias arm reads `ArrTypeDynDepth` correctly — and it was the SYMBOL built from
it that dropped the depth. The literal `function F: array of array of T`
spelling does hardcode `retDynDepth := 1`, but **fpc rejects that syntax
outright** (*"Type identifier expected"*), and pxx refuses the nested form
loudly, so nothing is lost there.

**Two more halves fell out, both the same mistake in a different place — a
consumer keyed on one SPELLING of a dyn-array value instead of on the value:**

1. `Length(MakeMat[1])` printed `25769803783` = `0x600000007`, the row's first
   two elements read as one 8-byte word. The IR arm that lifts a dyn-array call
   result for `Length` tested `AN_CALL and ProcRetIsDynArray` and hardcoded
   depth 1; the parser had already lifted `MakeMat[1]` into an `AN_COMMA`, which
   that test cannot see. It now keys on `(not IsASTLValue) and NodeDynDepth > 0`
   and takes depth/element from the node.
2. `for i in MakeMat[1]` said *"undefined variable (MakeMat)"* — the for-in
   qualified-source dispatch resolved the name with `FindSym` only, so a PROC
   arrived at `ParseLValueAST` as `idx = -1`. Same fix as the `High`/`Low` arms:
   parse the source with `ParseExpr` when the name is a proc.

And `AN_COMMA` — the node the call-result materialisation builds — was missing
from `NodeDynDepth` / `NodeDynBaseTk` / `NodeDynBaseRec` / `NodeDynBaseSym`
(`ast_arena.inc`) and from `DynArrayNodeDepth` (`symtab.inc`), so a lifted
dyn-array value stopped being a dyn array to every shape query at once.
`ResolveNodeRec` had had the comma arm since the csmith struct-through-a-comma
fix; the dyn-array twins never got it.

> **The two depth functions are twins and they drift.** `NodeDynDepth`
> (ast_arena) and `DynArrayNodeDepth` (symtab) answer the same question, and
> `DynArrayNodeDepth`'s own AN_INDEX arm already carries a note about having
> fallen behind its sibling once before. Both got the comma arm in one edit, and
> a note now sits in each pointing at the other. Merging them is the real fix
> and is a Track A refactor, filed separately.

Also removed: the depth>1 refusal added to the for-in arm in `3fba47f2b`, which
existed only to avoid trading a loud error for this crash. It is unnecessary now
— nested for-in over a call result matches fpc.

Regression: `test/test_a_nested_dynamic_array_result.pas`, wired into
`test-core`, `.expected` = fpc 3.2.2's own output. It asserts the callee-side
read, `SetLength` through `Result`, depth 3, a managed base element, the direct
call-result index, `High`, and both for-in spellings.

Gate: `make compiler/pascal26` converged in 1 round, `tools/gate.sh quick`
GREEN, fpc-testsuite conformance unmoved.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
