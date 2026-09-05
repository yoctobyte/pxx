---
slug: bug-a-xtensa-cannot-return-a-dynamic-array-from-a-function
track: A
prio: 35
type: bug
status: done
found: 2026-09-01
found-by: frankA
blocked-by: []
summary: "STALE AS FILED, verified by running: xtensa has NOT refused `function f(...): array of T` since the cross-target dynarray fix landed. Measured 2026-09-05 -- x86-64, riscv32 and xtensa all compile it and all print `len 5 sum 30`, and the two guards in symtab.inc are now structurally identical, both handling the dyn-array case before the ordinal/float/pointer/string check they were said to fail. The ticket's LAST clause was the part still true and is what got fixed here: the dyn-array ownership guards in ir_codegen_xtensa.inc had become reachable without anything starting to assert them, and xtensa was the one target with no test_dynarray_ownership_leaks row. That row is now wired."
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


## Resolved 2026-09-05 (frankS) — stale, plus the residual it correctly named

### The refusal is gone, and reading would not have told me

The ticket cites `symtab.inc:12364` for xtensa and `:12476` for riscv32. Both
line numbers have drifted; the refusals now live at 13691 and 13803, and **the
two guards are character-for-character the same shape**, each handling the
dyn-array result as a single pointer-sized heap handle BEFORE the
ordinal/float/pointer/string check the ticket says xtensa fails. Fixed under
`bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target`,
which is named in riscv32's comment.

Measured rather than inferred from the diff — one program, three targets:

```pascal
function MakeArr(n: Integer): array of Integer;
begin SetLength(Result, n); for i := 0 to n-1 do Result[i] := i*3; end;
```

| target | result |
| --- | --- |
| x86-64 | `len 5 sum 30` |
| riscv32 | `len 5 sum 30` (local qemu RUN) |
| xtensa | `len 5 sum 30` (local qemu RUN) |

### What was still true, and is the actual work

The ticket's closing clause: *"the two dyn-array ownership guards in
ir_codegen_xtensa.inc are correct but currently unreachable through a function
result."* The unreachability ended when the refusal was lifted. **Nothing
started watching them at that moment** — i386, aarch64, arm32 and riscv32 all
had a `test_dynarray_ownership_leaks` row and xtensa did not, because the row
had been omitted for a reason that had since stopped being true. Code that
becomes reachable without acquiring an assertion is the quiet half of this
class, and it is the same shape as the SysOpen refusals landed earlier today.

`test-core` now carries the xtensa row. It uses `-dPXX_ALLOC_CENSUS` and
compares against the x86-64 build of the same source, which is the right
ASSERTION CLASS for the defect class: an ownership bug does not corrupt a
value, it fails to give memory back, so every output row would pass a plain
value check. The census puts allocs/frees/live IN the output.

Measured, LOCAL QEMU RUN: byte-identical to x86-64 across all four phases
(direct, indirect, virtual, interface), ending `allocs=7707 frees=7703 live=4`
on both, exit 0.

### Note for whoever files the next one of these

The staleness was not detectable by reading — the cited line numbers still point
at real code in the right function, which is the failure mode CLAUDE.md warns
about: a stale line number does not error, it points somewhere. Running the
three-line repro settled it in under a minute.
