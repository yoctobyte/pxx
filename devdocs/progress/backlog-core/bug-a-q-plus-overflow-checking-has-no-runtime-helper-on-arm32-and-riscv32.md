---
slug: bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32
track: A
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-08-29
owner: unassigned
summary: "`{$Q+}` (overflow checking) fails to COMPILE for arm32 and riscv32 -- `{$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)`, raised from builtin/softfloat.pas. x86-64 and aarch64 build the same source. Split out of the aarch64 aggregate-result ticket, where it was recorded as an unrelated second finding so it would not be re-discovered as new."
---

# `{$Q+}` overflow checking has no runtime helper on arm32 and riscv32

- **Type:** bug — **Track A** (32-bit backends / runtime helper wiring).
- **Found:** 2026-08-29, alongside
  [[bug-a-aarch64-cannot-build-programs-with-an-aggregate-result-past-8-params]],
  which recorded it verbatim as *"Also seen, same session, unrelated cause"* and
  said to split it out if someone took that ticket. Someone did (frankA,
  2026-08-30), so here it is.

## Repro

```
$ pascal26 --target=arm32   test/test_a64_leafsym_binops.pas /tmp/x
pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)
$ pascal26 --target=riscv32 test/test_a64_leafsym_binops.pas /tmp/x
pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found (builtinheap not loaded)
```

Still reproduces at `bfd6e7f0e` with a self-hosted `8444cdce006a`. x86-64 and
aarch64 compile the same file. The error is raised while compiling
`builtin/softfloat.pas`, not the test program, so it is not specific to this
test — it fires for anything that reaches `{$Q+}` code on those two targets.

## Why it is filed separately rather than left where it was found

It shares nothing with the aggregate-result bug but the session that saw it: a
different diagnostic, different targets, different mechanism (a missing runtime
helper rather than an ABI lowering gap). Keeping the two in one ticket meant the
aggregate-result fix would close a ticket that still contained a live, unfixed
second defect — the shape that turns a `done/` entry into a thing nobody rereads.

## What is NOT yet known

**The root cause is unverified.** The message says `builtinheap not loaded`,
which reads as a unit-loading/ordering question rather than a missing
implementation, but nobody has checked whether `PXXOverflow` exists at all for
these targets, whether it exists and is not linked, or whether `{$Q+}` should be
lowering to an inline check on 32-bit instead of a helper call. That is the
first thing to establish, and it decides whether this is a five-line wiring fix
or a codegen gap.

## Cost

`{$Q+}` is how a program asks for arithmetic overflow to be *detected* rather
than silently wrapped, which makes an unbuildable `{$Q+}` a safety feature that
is unavailable on two of six targets — and unavailable loudly, at compile time,
so nothing silently mis-runs. That is the good version of this failure: it
refuses rather than pretending. It still means 32-bit code cannot be built with
the checking its author asked for.

## Gate

`make compiler/pascal26` + `test/test_a64_leafsym_binops.pas` compiles and runs
for arm32 and riscv32 with output matching the x86-64 oracle, plus a `{$Q+}`
program that actually overflows being caught on both targets — the point of the
directive is the trap firing, and a build that merely compiles proves only half.
