---
slug: umbrella-cross-target-codegen-is-correct
title: "Cross-target codegen is CORRECT — xtensa, riscv32, arm32, i386"
track: A
prio: 80
type: umbrella
blocked-by: [bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs, feature-a-port-alloca-to-i386-arm32-and-riscv32, bug-a-i386-c-main-gets-argc-and-argv-swapped, bug-a-riscv32-and-xtensa-still-refuse-aggregate-results-via-virtual-and-indirect-calls-under-a-done-ticket, feature-a-i386-refuses-a-by-value-record-parameter-on-the-internal-convention-so-lib-rtl-image-does-not-build, feature-a-a-stackful-generator-is-x86-64-only-so-examples-chess-cannot-target-anything-else]
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
