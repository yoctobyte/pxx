---
slug: bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets
track: A
prio: 50
type: bug
status: done
owner: frankA
blocked-by: []
resolved: PENDING-COMMIT
summary: "FIXED 2026-08-31 on all five cross targets, verified under each runner and against the pre-fix binary. Two defects, not one. (A) an OUT-OF-RANGE ParamStr was unbounded on i386/arm32/aarch64/riscv32/xtensa: `ParamStr(ParamCount+1)` dereferences argv[argc], the vector's own NULL terminator, and a larger index reads envp out as a string -- three targets SIGSEGV'd on the first nil, two printed 62 characters of environment memory first and crashed on the managed path. x86-64 alone compared against argc. (B) the frozen clamp answered 256 on aarch64/arm32/i386 where x86-64, riscv32, xtensa and FPC answer 255. Each backend now bounds the index and yields nil out of range, which `PXXCStrToFrozen` already turns into ''. New test/test_paramstr_out_of_range.pas plus test_paramstr_long_arg wired into all five per-target recipes and into a native row that asserts the oracle. Design half filed separately: only x86-64 still open-codes the filler the other five call."
---

# argv → frozen string: four targets never checked, and the clamp is per-path

Split out of `bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp`, which
fixed x86-64. That ticket said aarch64 / arm32 / i386 / xtensa "show no call to
either and want checking as part of this ticket". **I did not check them**, and
this ticket exists so that stays visible rather than being implied closed by a
resolution that only names x86-64.

## Why it was not done in the parent

This box builds those targets but does not run them. A "target X is fine" claim
from a successful compile alone is an unverified limit, and unverified limits get
believed rather than re-tested — the parent's own resolution turned on *running*
FPC and comparing, not on reading code.

## What is known

| path | clamp | limit |
| --- | --- | --- |
| x86-64 `EmitArgvToString` | yes, as of the parent fix | `FROZEN_CSTR_CAP` = 255 |
| riscv32, xtensa | yes, via `PXXCStrToFrozen` | `len < 255` |
| aarch64, arm32, i386 | **unknown** | **unknown** |
| managed destination (all) | none, correctly — sized from the length | n/a |

`ParamStr(i)` in expression position desugars to a hidden **frozen** temp of
`LOCAL_STR_CAP + 8` = 264 bytes, so any target that fills one with an unbounded
`strlen(argv[i])` has the parent's bug: a write past the slot into the
neighbouring frame slot, plus a stored length larger than the capacity.

## What to do

1. For each of aarch64, arm32, i386: find the argv→frozen fill and check whether
   it bounds the length. `grep` is the start, not the answer — the parent's fill
   was inline emitted bytes with no helper call, which is exactly what a
   call-site grep misses.
2. **Run** `test/test_paramstr_long_arg.pas` under each target's runner with a
   300-byte argument. It already asserts the whole contract (255 for the frozen
   rows, 300 for the managed row, and `done` reached), so it needs no per-target
   variant — only a runner. The existing xtensa argv row in the Makefile
   (`test_arm32_arg_runtime.pas` via `tools/run_target.sh`) is the pattern.
3. The expected answer everywhere is **255**, because that is what FPC answers
   and what the two clamped paths already produce.

## The design half, which is the reason a third copy will happen

`EmitArgvToString` (emitted x86-64 bytes) and `PXXCStrToFrozen` (an RTL routine)
implement the same contract **twice**. They now agree on the number, so there is
no observable divergence today — but the agreement is a coincidence maintained by
hand, and a target added tomorrow gets a third copy and a third chance to pick a
different limit. `normalise-dont-special-case` says one filler, called by every
backend, the way riscv32 and xtensa already call one. That is the real fix and it
is bigger than a bounds check, which is why it is written down here instead of
being done quietly inside a p70 hang fix.

## Measured 2026-08-31 by frankA — run, not read, on every target

`test/test_paramstr_long_arg.pas` with a 300-byte argument, under each target's
runner. **Two arguments** (so `argv[2]` exists), which is what separates the two
defects:

```
x86-64 : count=2 expr[1]len=5 expr[2]len=255 managed=300 done
aarch64: count=2 expr[1]len=5 expr[2]len=256 managed=300 done
arm32  : count=2 expr[1]len=5 expr[2]len=256 managed=300 done
i386   : count=2 expr[1]len=5 expr[2]len=256 managed=300 done
riscv32: count=2 expr[1]len=5 expr[2]len=255 managed=300 done
xtensa : count=2 expr[1]len=5 expr[2]len=255 managed=300 done
```

**(A) the clamp**: aarch64, arm32 and i386 answer **256**, everything else and
FPC answer **255**. Exactly the three the parent ticket flagged as unknown. Not a
smash — they reach `done` — but a cross-target and FPC-parity divergence.

**(B) the bound, which the ticket did not ask about and is the worse half.** The
same file with ONE argument reaches `ArgStr(2, s)` with `argv[2]` past the end,
and five of six targets fault. Reduced:

```pascal
program oor;
var s: string; n: Integer;
begin
  WriteLn('count=', ParamCount);
  WriteLn('frozen=', Length(ParamStr(3)));
  n := 3; ArgStr(n, s);
  WriteLn('managed=', Length(s));
end.
```

run with no arguments at all:

```
x86-64 : count=0 frozen=0   managed=0     <- correct, and the only one
aarch64: count=0 frozen=62  managed=62
arm32  : count=0 frozen=62  managed=62
i386   : count=0 frozen=62  managed=62
riscv32: count=0 frozen=62  managed=62
xtensa : count=0 frozen=62  managed=62
```

**62 characters of somebody else''s memory.** The index is scaled and added to
the argv base with no comparison against `argc`, so it reads past the array''s
NULL terminator into **envp** — the 62 bytes are an environment string. Where the
slot past argv is unmapped it segfaults instead, which is what the two-argument
run above showed.

x86-64 is right because `EmitArgvToString` opens with an explicit
`cmp rax, argc; jb in_range` and stores `''` otherwise. That check exists in
exactly one of six backends.

### The comment that stood in for the check

`compiler/ir_codegen_riscv32.inc`, on the load:

```
rv32_lw(reg_a0, reg_a0, 0);   { argv[index] (or junk past envp for a huge index
                                — Pascal callers pass 0..ParamCount) }
```

Pascal callers do **not**. `ParamStr(1)` with no arguments is legal and FPC
returns `''`. The precondition was written down instead of being enforced, and
then read as though it were enforced —
[[a-comment-recording-a-bug-is-not-a-guard-against-it]].

### `PXXCStrToFrozen` already answers half of it

It takes `src = nil` and produces `''`, and it caps at 255. So on the frozen
path each backend only owes **nil for an out-of-range index** and both halves
fall out. The managed path (`PXXStrFromLit` after an inline `strlen`) needs the
bound before the strlen loop, or it walks off nil.

## Revised plan

1. Bound the index against `argc` in each of the five cross backends, producing
   a nil source pointer out of range. Frozen then yields `''` via
   `PXXCStrToFrozen`; managed needs its own nil arm.
2. Land per target, verified under that target''s runner against the x86-64
   answer, not against a reading of the diff.
3. Delete the riscv32 comment quoted above — it is the false half of a
   [[the-name-is-not-the-thing]] pair, and the code is what was wrong.

## The design half, restated with the real duplication

The parent worried about a third copy of the CLAMP. Measured, the clamp is
already shared: five of six backends call `PXXCStrToFrozen`, and only
**x86-64''s `EmitArgvToString` reimplements it inline** — its own strlen, its own
`cmp rcx, FROZEN_CSTR_CAP`, its own `rep movsb`. That is the duplication, it is
one copy not three, and normalising it means making x86-64 call the RTL routine
the other five already use. Separate change, no observable behaviour, so not
bundled with a crash fix.

## Fixed 2026-08-31 — both defects, all five targets, run not read

Each cross backend now compares the index against `argc` and produces a **nil**
source pointer when it is out of range. That single change answers both halves
on the frozen path, because `PXXCStrToFrozen` already maps `nil` to `''` and
already caps at `FROZEN_CSTR_CAP` = 255; the managed path needed its own nil arm
before its inline strlen loop, which is where riscv32 and xtensa were still
crashing after the frozen path was correct.

Per target, and they are not the same edit:

| target | bound | nil arm on the managed path |
| --- | --- | --- |
| i386 | `cmp eax,[ecx]` / `jb`, `xor eax,eax` out of range | `test esi,esi` / `jz` |
| arm32 | predicated: `cmp r0,r2` then `lslcc/addcc/ldrcc`, `movcs r0,#0` | `cmp rX,#0` / `beq` |
| aarch64 | `ldr x2,[x1]`, `cmp x0,x2`, two `csel x0,x0,xzr,lo` | `cbz x3` |
| riscv32 | branch-free: `sltu` + `sub` from zero → a mask, ANDed over both the index and the loaded pointer | `beq` before the strlen loop |
| xtensa | `bgeu a2,a9,.oor` in the existing `EmitAsmXtensa` block | `beq a3,a6,.done` first in the loop |

The three that also answered **256** (aarch64, arm32, i386) now clamp with
`FROZEN_CSTR_CAP` rather than a literal, so the constant has one definition.

### Verified under each runner, both directions

`test/test_paramstr_out_of_range.pas` (new) with no arguments, and
`test/test_paramstr_long_arg.pas` with a 300-byte argument. All six targets:

```
oor : count=0 nil=0 lit=0 var=0 managed=0 nilmanaged=0 done
long: count=2 expr[1]len=5 expr[2]len=255 managed=300 done
```

**And the same rows against `pinned`, which is the pre-fix compiler** — because
a test written after a fix that has never failed is not a test:

```
i386 aarch64 arm32   nil= SIGSEGV                        (frozen fill, first nil)
riscv32 xtensa       nil=0 lit=62 var=62 managed=62 then SIGSEGV
i386 aarch64 arm32   long: expr[2]len=256                (the clamp half)
```

Every row fires on the old binary and passes on the new one, on every target it
is wired to. The riscv32/xtensa split is the reason the new test has SIX rows
and not two: a probe that stopped at `nil=` would have called those two clean
while they were still reading environment memory out as a string.

### Wired

`test-i386`, `test-aarch64`, `test-riscv32`, `test-xtensa`, `test-arm32` each
gained both rows, compared against the x86-64 build of the same program. The
x86-64 oracle is itself asserted by a native row against a literal expectation —
otherwise a regression in the one backend that was always right would make all
five cross rows agree on the wrong answer and stay green.

### The third row that is not in the table

`ParamStr(3)` and `ParamStr(n)` are both in the test on purpose. Only the
variable form was exercised before, and a literal index is the arm any future
constant-fold would take. Neither costs anything to keep.

### Design half — filed, not bundled

`feature-a-one-argv-to-frozen-filler-instead-of-x86-64s-inline-copy`. Measured,
the duplication is **one copy, not three**: five of six backends already call
`PXXCStrToFrozen`, and only x86-64's `EmitArgvToString` reimplements it as
emitted bytes. No observable behaviour, so it does not belong in a crash fix.
