---
track: C
prio: 45
type: bug
status: new
blocked-by: []
owner: ""
summary: "A plain C function taking a `float` and returning a `float` gives 0.00 on arm32 and riscv32 and -7.55e307 on i386, in a pure C program, today. Nothing to do with the calling-convention work -- riscv32 is untouched by it and still fails. Found while baselining the control for that ticket."
---

# A `float` parameter and return are wrong in pure C on three targets

Found on 2026-08-30 while measuring the baseline for
`test/c_abi_pure_c_control.c` — the control for
[[bug-c-a-c-function-s-calling-convention-depends-on-the-target]]. I had
asserted that control was green on all five targets having checked only x86-64.
It was not, and this is why.

## The shape

```c
float cee_flt(float f, int n) { return f * (float)n; }
...
printf("flt %.2f\n", (double)cee_flt(2.5, 4));   /* want 10.00 */
```

Pure C program, compiled by pxx, no Pascal anywhere. Compiler `8a42f93ffe74`.

| target | `flt` |
| --- | --- |
| x86-64 | 10.00 |
| aarch64 | 10.00 |
| arm32 | **0.00** |
| riscv32 | **0.00** |
| i386 | **-7.55e307** |

Every other shape in the same program — `f(double,int)`, `f(int,double)`,
`f(int,int,int)`, `f(double,double)` — is correct on all five. It is `float`
specifically, not floating point generally, which is why this is a **bug in its
own lane and not Track F**: the mechanism is a wrong signature/classification
for a 4-byte float, and the datatype being floating point is incidental. Rank
the mechanism, never the datatype.

## Why it is separate from the convention ticket

**riscv32.** That ticket's fix does not touch riscv32 at all — riscv32 keeps its
local `cparser.inc` arm and has no `ProcCdecl` branch in the shared one — and
riscv32 fails this today. The convention work can neither have caused it nor
will fix it.

It is also visible with no Pascal in the picture, where the convention ticket's
whole subject is a Pascal caller meeting a C callee.

## Not yet investigated

Whether the defect is in the argument (a `float` arriving as double bits and
being read as a raw single, or the reverse) or in the return path, or both. The
i386 value is garbage rather than zero, which suggests those three targets may
not share one cause. Vary the shape — `float` argument with `double` return, and
`double` argument with `float` return — before assuming one fix covers all three.
