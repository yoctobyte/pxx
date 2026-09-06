---
slug: umbrella-cross-target-codegen-is-correct
title: "Cross-target codegen is CORRECT — xtensa, riscv32, arm32, i386"
track: A
prio: 80
type: umbrella
blocked-by: [bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs, feature-a-port-alloca-to-i386-arm32-and-riscv32, bug-a-i386-c-main-gets-argc-and-argv-swapped, feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross, refactor-a-the-scope-exit-managed-local-release-loop-has-seven-copies]
created: 2026-08-31
summary: "GOAL, not a unit of work. The owner's ranking: 'cross platform has way prio above look-if-I-do-this-on-platform-that-it-would-break-z'. A program that compiles right on one target and wrong on another is the defect this umbrella exists for; a hypothetical about an untried platform is not. Measured target clusters: xtensa 11, riscv 8, arm32 5, i386."
---

# Cross-target codegen is correct

*"cross platform has way prio above 'look if i do this on platform that it would
break z'."* — the owner, 2026-08-31, distinguishing a **measured divergence**
from a **speculated** one.

## The line this umbrella draws

**In:** a real program that compiles correctly on x86-64 and incorrectly on
another target. That is cross-cross failing, and it is expensive.

**Out:** "if someone did X on platform Y it would break." No program reached it,
nothing measured it. That is a `bugnotes.md` paragraph.

The hosted-xtensa divergence wired here is the model: **21 cross programs**
disagreeing with the oracle, measured, not imagined.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.


## 2026-09-02 (frankC) — an attempt, and what it named

Attempted the cell the way this umbrella asks: compiled `examples/` for
i386/arm32/riscv32/aarch64/xtensa against the x86-64 oracle, **comparing bytes**.
18 programs reached a runnable oracle; **11 were green on all five**. The rest
named, in the order they turned up:

| program | finding | disposition |
| --- | --- | --- |
| 5 of 6 sysutils users | xtensa refused a dynamic-array RESULT, so `lib/rtl/sysutils.pas` itself did not build | FIXED `7cc404961` |
| satdemo, fm | a `var` dynamic-array param read one deref short on riscv32 + xtensa; silent 0s, writes into the caller's stack | FIXED `eabd599ee` |
| jsondemo | riscv32 + xtensa still refuse aggregate results via virtual/indirect calls, under a ticket in `done/` | filed, blocker |
| fm, raytracer | `lib/rtl/image.pas` unbuildable on i386 — by-value record param, and **the refusal is correct** | filed, blocker |
| chess | stackful generator is x86-64-only; the stackless spelling works on all six | filed, blocker |
| mathdemo | `sin` wrong on both SOFT-FLOAT targets, byte-identically — one shared implementation | filed in `float/` (F) |
| console_2048, menudemo | TUI output diverges on riscv32 + xtensa, identically | not yet investigated |

Two of these were RTL units that did not build for a target at all, which is
worth more than the count suggests: one missing epilogue arm took out every
program using `sysutils` on the ESP ABI, and no test could say so because the
relevant regression ran on x86-64 only.

**Correction to something I wrote earlier the same day:** I reported this
umbrella as having "no blockers, so nobody has attempted the cell". That was
wrong and the instrument was the mistake — I grepped the backlog for files
*mentioning* this slug, and the edge lives in this file's own `blocked-by`,
where three blockers already sat. A grep that returns nothing is not the same as
an empty list.


## 2026-09-02 (frankC) — the SECOND attempt, at `c2e9bbafd`

Same instrument as the first, whole `examples/` tree this time (39 programs, 19
skipped for want of a runnable x86-64 oracle), bytes compared against x86-64.

**Every row the first attempt named is now green except the two that were
already filed elsewhere.**

| program | first attempt | now |
| --- | --- | --- |
| fm | i386:BUILD riscv32:RUN(139) xtensa:RUN(139) | **ok on all five** |
| raytracer | i386:BUILD | **ok on all five** |
| jsondemo | riscv32:BUILD xtensa:BUILD | **ok on all five** |
| chess | BUILD on all five | **ok on all five** (see the timeout note below) |
| console_2048, menudemo | riscv32:DIFF xtensa:DIFF | **ok on all five** |
| satdemo | riscv32:RUN(139) xtensa:RUN(135) | **ok on all five** |
| mathdemo | riscv32:DIFF xtensa:DIFF | unchanged — filed in `float/` (F) |

14 programs green on all five targets. Three rows are not:

- **`mathdemo`** — `sin` on both soft-float targets, byte-identically. Already
  filed under F, still the same shape.
- **`httpdemo`** — NEW, and the first attempt never saw it because it ran a
  hand-written program list rather than the tree. Stackful coroutines exist for
  four targets. Filed:
  `feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross`.
- **`uses_tkinter_and_configparser`** — NEW, fails on all five, and on **four
  different causes**. Filed:
  `bug-a-the-tkinter-demo-hits-a-different-backend-gap-on-i386-and-on-arm32`.

### `chess | xtensa:RUN(124)` was the instrument, not the program

The sweep reported a failure here and it was my 90-second timeout: run under
`qemu-xtensa` with 600s, chess finishes in **1m57s** and its output is
byte-identical to the oracle. Recorded because the next reader of that table
would otherwise chase a defect that does not exist — a timeout does not error,
it answers.

## 2026-09-06 (frankF) — the FRONTEND x ESP-TARGET cell, attempted rather than triaged

Under a release advertising "all frontends and all targets" this is the cell
nobody had printed. One hello-world per frontend, `d6de711d1`,
`compiler/pascal26 = c9de36a3754e`, `converged after 1 round(s)`.

| frontend | esp32s3 bare | esp32c3 bare | riscv32 IDF | xtensa IDF (call0 / windowed) |
| --- | --- | --- | --- | --- |
| Pascal | **OK** | **OK** | **OK** | **OK / OK** |
| C | refuses (entry stub) | `compiler error: PXXMemZero not found` | same | same |
| NilPy | refuses (heap arena needs mmap) | refuses (same) | refuses (same) | refuses (same) |
| Zig | refuses (x86-64 only) | refuses | refuses | refuses |
| Rust | refuses (x86-64 only) | refuses | refuses | refuses |

**Pascal is the only frontend that reaches an ESP target at all**, on either
profile and either ISA. That is the whole row, and it is worth having written
down before anyone writes "all frontends, all targets" in release copy.

**Most of these are not defects, and the distinction is the useful part.**
Zig and Rust are Track X and answer *"only the x86-64 target is supported by the
skeleton"* — an honest refusal from an experimental frontend, which is a
frontend working. NilPy answers *"a heap arena needs mmap, which this profile
has not"* — a true statement about a real constraint
([[bug-a-nilpy-on-cross-targets-four-remaining-walls]]). A refusal that names
its reason is not a red; it is a target that has not been reached yet, and the
release copy should say which frontends reach ESP rather than implying five do.

**Two things here ARE defects:**

1. **C on esp32c3 answers `compiler error: PXXMemZero not found`** — an
   internal-fault-shaped diagnostic for `#include <stdio.h>` plus a `printf`.
   Already filed and correctly diagnosed:
   [[bug-s-c-on-the-esp-profile-cannot-reach-crtl]] (S, p45) — the symbol exists
   unconditionally in `builtinheap.pas`, so the lookup is not reaching it. This
   attempt adds one row that ticket does not have: **the two ESP ISAs give
   DIFFERENT diagnostics for the same source.** esp32s3 bare refuses cleanly
   with the entry-stub message; esp32c3 bare reaches the compiler error. Same
   source, same profile, one chip apart.

2. **NilPy's refusal on the xtensa IDF profile says "which BARE METAL has
   not"** — and that build is not bare metal. riscv32 gets the correct wording
   (*"which this profile has not"*), so the xtensa arm hardcodes the word. Same
   "xtensa MEANS bare metal" conflation that
   [[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]] was filed
   for and closed; this is message text left behind, not a returning defect.
   Small, but it tells a reader the wrong thing about why their IDF build failed.

**Method note.** Every cell is a real invocation, not a table maintained by
hand. Executables for the bare profile; `--emit-obj` for IDF, because that is
the shipping path there. The Pascal row is corroborated by 29 executed qemu
assertions the same evening ([[bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it]]),
so its OK is "runs and matches the x86-64 oracle", while every other OK in this
table would only have meant "compiled".
