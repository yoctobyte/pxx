---
slug: bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets
track: A
prio: 50
type: bug
status: working
owner: frankA
blocked-by: []
summary: "MEASURED 2026-08-31, and it is BIGGER than filed. Two defects, not one. (A) the frozen clamp answers 256 on aarch64/arm32/i386 where x86-64/riscv32/xtensa and FPC answer 255. (B) THE ONE THAT MATTERS: an OUT-OF-RANGE ParamStr is unbounded on all FIVE cross targets -- `ParamStr(3)` with ParamCount=0 returns a 62-character string of ENVIRONMENT bytes on aarch64, arm32, i386, riscv32 and xtensa, and segfaults outright when the slot past argv is unmapped. x86-64 alone bounds the index against argc and returns ''. This is ordinary code -- `ParamStr(1)` before checking ParamCount -- so it is a crash and an information leak, not an edge case. The riscv32 source carries a comment saying `Pascal callers pass 0..ParamCount`, which is not true of the language and was read as a guard."
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
