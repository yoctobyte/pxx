---
track: P
prio: 45
type: bug
blocked-by: []
status: backlog
summary: "`type TFixOfDyn = array[0..1] of TRow; var f: TFixOfDyn;` then `SetLength(f[0], 1)` is refused with `SetLength expects an array variable in IR codegen`, while the identical INLINE declaration `var f: array[0..1] of TRow` compiles and runs. The array-type table has no ArrTypeElemDynDepth, so the named-type path cannot thread the element's dyn depth into SymElemDynDepth."
---

# A named `array[0..1] of TRow` type loses its element's dyn depth

Found 2026-08-22 while fixing
`bug-p-open-array-of-a-named-dynamic-array-reads-garbage`. Pre-existing —
reproduced on `stable_linux_amd64/default/pinned`, so it is not a regression
from that fix.

## Repro

```pascal
program oa22;
type TRow = array of Integer;
     TFixOfDyn = array[0..1] of TRow;
var f: TFixOfDyn;
begin
  SetLength(f[0], 1); f[0][0] := 1;
  Writeln(f[0][0]);
end.
```

```
pascal26: error: SetLength expects an array variable in IR codegen
```

fpc accepts it and prints `1`. Replace the declaration with the inline form:

```pascal
var f: array[0..1] of TRow;
```

and pxx compiles and runs it correctly. Same type, two spellings, one works.

## Root cause (located, not fixed)

`ParseDeclTypeDesc` (`compiler/pasparser_decl.inc`) sets `VDElemDynDepth` when
it parses an INLINE fixed array whose element resolves to a dyn-array alias
(~line 890); `AllocArray` threads that into `SymElemDynDepth`, which is what the
whole "each slot is a pointer-sized handle" machinery in `ir.inc` /
`ast_arena.inc` keys on.

The **named-type** branch a hundred lines earlier (`if ai >= 0 then` — "Variable
of a named array type") copies `ArrTypeElemTk`, `ArrTypeElemRec`,
`ArrTypeElemRowLen/Lo`, the dims and the dyn depth of the OUTER array — but
there is no `ArrTypeElemDynDepth` field to copy, because `ParseTypeSection`
never recorded one when it registered `TFixOfDyn`. So the var gets
`SymElemDynDepth = 0` and its elements are laid out as base scalars.

## Shape of the fix

Add `ArrTypeElemDynDepth` next to `ArrTypeElemRowLen` in `defs.inc`, stamp it in
`ParseTypeSection` where a fixed array's element resolves to a dyn alias
(the same test the inline path makes: `FindArrayType(name) >= 0` and
`ArrTypeIsDyn`), and read it into `VDElemDynDepth` in the named-type branch.
Then **grep the siblings before closing**: record fields (`fDynDepth` around
`pasparser_decl.inc:3185` and `:4777`) and class fields go through their own
copies of this decision and may have the same hole.

## Gate

`make compiler/pascal26` + a test asserting the named and inline spellings agree
(and both agree with fpc) + `tools/gate.sh quick`.
