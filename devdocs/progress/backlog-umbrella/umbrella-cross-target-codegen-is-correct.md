---
slug: umbrella-cross-target-codegen-is-correct
title: "Cross-target codegen is CORRECT — xtensa, riscv32, arm32, i386"
track: A
prio: 80
type: umbrella
blocked-by: [bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs, feature-a-port-alloca-to-i386-arm32-and-riscv32]
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
