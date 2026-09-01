---
slug: bug-a-xtensa-cannot-return-a-dynamic-array-from-a-function
track: A
prio: 35
type: bug
status: open
found: 2026-09-01
found-by: frankA
blocked-by: []
summary: "`function MakeArr(n: Integer): array of Integer` is refused outright on --target=xtensa with 'target xtensa: only ordinal/float/pointer/string function results supported yet' (symtab.inc:12364), while riscv32 -- which carries a refusal of the same shape at symtab.inc:12476 -- accepts it and runs it correctly. So the gap is xtensa's list being narrower than its sibling's, not a missing mechanism. It is why test/test_dynarray_ownership_leaks.pas has no xtensa row, and it means the two dyn-array ownership guards in ir_codegen_xtensa.inc are correct but currently unreachable through a function result."
---

# xtensa cannot return a dynamic array from a function

## Repro

```pascal
program XtMin;
type TIntArr = array of Integer;
var a: TIntArr;
function MakeArr(n: Integer): TIntArr;
begin SetLength(MakeArr, 4); MakeArr[0] := n; end;
begin a := MakeArr(7); WriteLn('v=', a[0]); end.
```

```
$ pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh xt_min.pas out
pascal26:6: error: target xtensa: only ordinal/float/pointer/string function
  results supported yet
$ pascal26 --target=riscv32 xt_min.pas out
ok:  [code=261996B ...]
```

Identical on the pinned stable compiler, so it is long-standing and not a
regression.

## Why riscv32 is the lead

`symtab.inc:12476` carries the *same sentence* for riscv32 and riscv32 accepts
this program, so that guard's accepted set has already been widened once for a
32-bit target and xtensa's was not. Read the riscv32 arm first and ask what it
admits that xtensa's does not; a second mechanism is unlikely to be needed.

## What it currently costs

- No xtensa row in `test/test_dynarray_ownership_leaks.pas` — the whole reason
  that file is separate from `test_managed_str_ownership_leaks.pas`.
- The two dyn-array ownership guards in `ir_codegen_xtensa.inc` were widened to
  `IRNodeOwnsFreshCallResult` with the other twelve. That is correct and
  consistent, but it is **not verified on xtensa by execution** and cannot be
  until this is fixed: no program can currently reach them through a function
  result. Stated here rather than implied by the sweep's silence.
