---
slug: bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets
track: A
prio: 50
type: bug
status: backlog
owner:
blocked-by: []
summary: "x86-64's argv->frozen-string copy is now clamped and riscv32/xtensa clamp via PXXCStrToFrozen, but aarch64, arm32 and i386 were never checked — the parent ticket listed them and I did not close that gap. Also: the clamp is duplicated per path rather than shared, so a new target gets a new copy."
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
