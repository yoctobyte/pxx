---
slug: umbrella-pxx-hosted-beyond-linux
title: "pxx HOSTED on a second platform — bsd, minix, gnu, windows"
track: A
prio: 85
type: umbrella
blocked-by: [feature-port-openbsd-libc, decide-openbsd-pinsyscalls-vs-the-rt-sigreturn-residual]
created: 2026-08-31
summary: "GOAL, not a unit of work. 'Run a minimal system with compiler' -- pxx HOSTED somewhere that is not Linux/x86-64, not merely cross-emitting to it. Self-host is proved here every ~12s by the build; the goal is that same property on another kernel. OpenBSD is the nearest rung and the only one with tickets today; minix 2/3 and Windows have NONE, which is information, not an oversight."
---

# pxx hosted on a second platform

*"pxx should run under linux/bsd/minix/gnu/windows/wasm 'kernels' ... and run a
minimal system with compiler."*

## Hosted, not cross-emitted — the distinction is the whole umbrella

We already emit code for many targets. This umbrella is about the compiler
**running there**: pxx on the box, compiling itself, reaching its own
fixedpoint. `make compiler/pascal26` proves that property on Linux/x86-64 every
twelve seconds; it proves nothing about any other kernel.

## The empty cells are the finding

OpenBSD has two tickets. **Minix 2, Minix 3, GNU and Windows have essentially
none** — and that is not a gap in the backlog, it is an accurate report that
nobody has attempted them. An umbrella with no blockers says *unattempted*,
which is exactly what a 400-ticket flat backlog could never say.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.
