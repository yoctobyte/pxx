---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`SetLength(TC.V, n)` on a dynamic-array `class var` compiled clean and SEGFAULTED on the next read — the qualified spelling makes SetLength's own operand lookup answer the CLASS, not the member, so idx was -1 and the target classification fell through every arm to the STRING one, writing a string header over the array handle. `New(TC.P)` is the same defect through its loud arm (\"New: undefined variable\" on a valid pointer class var)."
---

# SetLength on a QUALIFIED class var writes a string header over the array

Found 2026-08-22 while re-measuring the `class var` gap banked in
[[feature-pascal-corpus-generics]] ("Gap 2 — `class var` takes no array at all").
That gap's *parse* half is fixed (the branch calls `ParseDeclTypeDesc` +
`AllocFromDeclTypeDesc`, the same pair the `var` section uses, so every array
form now declares correctly). What was left is the *use* half, and it is a
different mechanism.

## Symptom

```pascal
type
  TC = class
  public class var
    FDyn: array of Integer;   { or a named `TDyn = array of Integer` }
  end;
begin
  SetLength(TC.FDyn, 3);
  TC.FDyn[1] := 5;            { SEGFAULT }
end.
```

Compiles clean. `fpc -Mobjfpc -O1` prints `3 5`. Both the inline
`array of Integer` and the named-dynamic-type spellings crash; a fixed array and
a `string` class var were already fine, which is what kept it hidden.

## Root cause — one defect, two doors

`FindVarSym` (pasparser_class.inc) was added so an intrinsic that resolves its
own operand sees a class var; its own comment records the exact failure:

> *For SetLength that arm classifies the target as a STRING, so `SetLength(G, n)`
> on a dynamic-array class var wrote a string header over the array handle and
> the next read segfaulted.*

That fixed the **bare** name a method body can use. The **qualified** spelling
`TC.V` walks straight past it: the name at the operand position is `TC`, which is
a CLASS, so every lookup — `FindSym` or `FindVarSym` — answers -1, and the
classification block below

```pascal
else if idx >= 0 then
  slIsArrTarget := (Syms[idx].IsArray and (Syms[idx].ArrLen = -1)) or ...
```

never runs. `slIsArrTarget` stays False, `BuildMultiSetLen` emits the string
SetLength (`call a=-101` instead of `-102`), and the handle is overwritten.

Measured, not inferred: `PXXDBG=a.ir:Go` on the repro against a plain global
`array of Integer` shows **twelve identical IR instructions** except
`call a=-101` vs `call a=-102`. The index lowering was never involved.

The block's own comment already stated the right rule — *"From the resolved
lvalue, not the base symbol"* — and then the last arm re-derived it from the base
symbol anyway. `ParseLValueAST` had resolved the member correctly all along.

## Fix

Read the symbol back off the node the lvalue parser returned, in both intrinsics
that classify from `idx`:

```pascal
valNode := ParseLValueAST(idx, identTokIdx);
if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) then
  idx := ASTIVal[valNode];
```

`compiler/pasparser_stmt.inc`, the `SetLength` arm and the `New` arm. For an
ordinary variable this is a no-op (the node's sym IS `idx`), so it normalises
rather than adding a case — `devdocs/dev/normalise-dont-special-case.md`.

## The sibling grep

The same shape (`FindSym` → `ParseLValueAST` → use `idx`) appears at five more
intrinsics in that file. Checked all five:

| intrinsic | uses `idx` after? | state |
| --- | --- | --- |
| `SetLength` | yes, to classify | **fixed** |
| `New` | yes, for the element size | **fixed** (was a loud `New: undefined variable`) |
| `ReallocMem` | yes, but has a working `idx < 0` fallback that reuses the lvalue | fine |
| `Include` / `Exclude` | no | fine |
| `LoadFile` | no | fine |

## Test

`test/test_class_var_of_a_managed_type.pas`, wired into `test-core`. Covers
inline-dynamic / named-dynamic / pointer / string class vars through the
qualified spelling, a descendant naming the same slot (`TDer.Inl`), and an
instance naming it (`o.Inl`). Output is line-for-line identical to
`fpc -Mobjfpc -O1` 3.2.2.

## Gate

`make compiler/pascal26` (fixedpoint, converged) + the repro + `tools/gate.sh quick`.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
