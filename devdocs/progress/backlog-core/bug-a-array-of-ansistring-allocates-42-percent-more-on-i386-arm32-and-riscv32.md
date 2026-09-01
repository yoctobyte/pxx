---
slug: bug-a-array-of-ansistring-allocates-42-percent-more-on-i386-arm32-and-riscv32
track: A
prio: 40
type: bug
status: open
found: 2026-09-01
found-by: frankA
blocked-by: []
summary: "Building `sa := MakeStrArr(i)` where the result is `array of AnsiString`, i386, arm32 and riscv32 perform 5411 allocations against x86-64's and aarch64's 3799 for byte-identical source and identical output -- 42% more, on the DIRECT call as much as the indirect one. Nothing leaks: frees track allocs (5406/5) and the live count is flat, so this is redundant work, not a lifetime bug, most likely an extra copy-on-write from a retain those three backends do and the other two do not. Measured with -dPXX_ALLOC_CENSUS on 91c293722 and on its child, so it predates the dyn-array ownership fix and is not caused by it."
---

# `array of AnsiString` allocates 42% more on i386, arm32 and riscv32

Found while sweeping the new `test/test_dynarray_ownership_leaks.pas` across
targets: four backends agreed exactly on every integer-array arm and split into
two groups on the string-element arm.

## The measurement

One program, `sa := MakeStrArr(i)` 2000 times, `MakeStrArr` returning
`array of AnsiString` with two elements set. Same source, same output
(`k=4000`) everywhere.

| target | direct call | indirect call |
| --- | --- | --- |
| x86-64 | allocs=3799 frees=3796 live=3 | 3799 / 3796 / 3 |
| aarch64 | allocs=3799 frees=3796 live=3 | 3799 / 3796 / 3 |
| i386 | **allocs=5411** frees=5406 live=5 | **5411** / 5406 / 5 |
| arm32 | **allocs=5411** frees=5406 live=5 | **5411** / 5406 / 5 |
| riscv32 | **allocs=5411** frees=5406 live=5 | **5411** / 5406 / 5 |

## What it is NOT

Not the ownership bug it was found beside. **The direct and indirect columns are
identical**, so it is not a call-kind discrimination — that was the whole shape
of `bug-a-an-indirect-call-returning-a-dynamic-array-leaks-every-allocation-on-every-backend`,
and this survives its fix unchanged.

Not a leak. `frees` tracks `allocs` and `live` is flat at 5 across the loop, so
nothing accumulates; `assert_no_leak.sh` passes on all five targets. The cost is
1612 wasted allocate/free pairs per 2000 iterations.

Not a regression from that fix: measured on **91c293722**, the parent commit,
where x86-64 already read 3799 and i386 already read 5411. An older pinned
binary reads 5411 on BOTH, so the x86-64 half was fixed somewhere between the
pin and 91c293722 and the three 32-bit backends were not carried along — that
commit is the place to look first.

## Where to look

The split is not 32-bit versus 64-bit: aarch64 is 64-bit and agrees with x86-64,
but riscv32/arm32/i386 are all 32-bit and agree with each other. Whatever landed
on x86-64 and aarch64 is a per-backend edit that the three others never got.
Grep the element-wise managed-array paths (`PXXDynArrayIncRef` /
`PXXStrIncRef` around `IR_STORE_SYM` for an array whose element TypeKind is
`tyAnsiString`) and diff the three against aarch64's.

Reproduce with `-dPXX_ALLOC_CENSUS` and the four-line program in the table above;
the arm is deliberately NOT wired into `test_dynarray_ownership_leaks.pas`
because pinning 5411 as expected would freeze the defect.
