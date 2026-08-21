---
track: U
prio: 50
type: decide
blocked-by: []
summary: "feature-a-riscv64-as-a-hosted-first-class-target is the top-ranked Track A ticket at prio 50, and its own log says it was ranked 'as a strategic target rather than an urgent one'. It is a multi-session job. An unattended overnight Track A session keeps reaching it, skipping it, and taking a p40 bug instead — which may be right, but it is a decision being made silently every night. Make it once, out loud."
status: backlog
---

# Should an autonomous Track A night start riscv64, or keep clearing the bug queue?

## The fork

`tools/progress.sh next --track A` returns
[[feature-a-riscv64-as-a-hosted-first-class-target]] (prio 50) every time. A
session that follows the ranker takes it; a session that reads it takes a bug
instead, because:

- Its own status line says *"the implementation is a multi-session job and is
  not started"*, and its log says prio 50 is *"a strategic target rather than an
  urgent one"*.
- The stated standing priority is the opposite shape: *"compiler syntax,
  segfaults, etc, all prio"* — bugs first.
- Nothing else in the A queue outranks it, so the skip repeats every session and
  is never recorded.

So the queue and the standing instruction disagree, and each session resolves it
privately. That is the thing worth fixing, more than either answer.

## What is actually ready to build

The design question the ticket calls *"the one thing to establish first"* is
**answered and measured** (2026-08-21, in the ticket): **widen
`ir_codegen_riscv32.inc`, do not fork it.** The evidence is in there — 140
`rv32_*` calls live OUTSIDE the backend across five files, 87 of them
width-sensitive, so a fork duplicates 3,441 lines and solves none of the real
problem. The staged plan is written out, including a located correctness trap
(RV32 masks shift amounts to 5 bits, RV64 needs 6, and the extra bit lands in
`funct7` — a shift by 32..63 would silently encode as a *different
instruction*).

An incremental, always-green path exists: every step keeps riscv32 output
**byte-identical** (checkable locally by compiling a corpus for riscv32 before
and after and `cmp`-ing), riscv64 stays unselectable until it runs, and
`qemu-riscv64` is already wired into `tools/run_target.sh`. So this is not a
long-lived-branch risk.

## Options

1. **Bugs first (recommended).** Keep the nights on the ranked bug/refactor
   queue; pick riscv64 up as a deliberate, supervised campaign. Rationale: it
   matches the standing "segfaults are prio" instruction, each bug lands green
   and complete within a session, and a half-built backend is the one thing
   `tools/progress.sh check` calls CRITICAL. Cost: riscv64 keeps not starting.
2. **Start riscv64 on autonomous nights, staged.** The plan is concrete enough to
   execute unattended and the byte-identical check makes each step verifiable.
   Cost: several nights produce a target that does not yet run anything, and the
   ranked bug queue keeps growing behind it.
3. **Re-rank instead of deciding.** Drop riscv64 to prio ~35 (or raise the bugs)
   so the ranker and the instruction agree, and let `next` be followed literally.
   This is the option that stops the question recurring, and it composes with
   either of the two above.

## Recommendation

**1 + 3.** Take the bugs on unattended nights, and drop riscv64's `prio` so the
queue stops telling every session something the standing instruction contradicts.
Then start riscv64 when someone is watching — its first real milestone
(self-hosting pxx on RISC-V) is worth a supervised run, and its shift-mask trap
is exactly the kind of silent-wrong-encoding bug that wants a human near it.

## Log
- 2026-08-21 — filed by the overnight Track A session, on the third consecutive
  time it declined the top of its own queue. Filed rather than guessed, per the
  escalate-don't-guess rule.
