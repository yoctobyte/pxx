---
title: "C preprocessor: a self-referential macro call left its arguments unexpanded"
status: done
owner: claude-dupwt
prio: 80
area: cfront
---

C 6.10.3.4p2: during the rescan of a macro's replacement, its own name is not
replaced again (it is "painted"). Only the NAME is painted, though. The
tokens after it are rescanned as usual. pxx copied the painted call's whole
argument list as-is, so a macro used inside those arguments never expanded.

FreeBSD's sys/malloc.h defines malloc as a macro over the malloc function:
`#define malloc(size, type, flags) ({ ... malloc(_size, type, (flags) &~
M_ZERO); ... })`. pxx left `M_ZERO` as an undeclared identifier there. That
was the first error in 1287 of the 2100 GPU-driver compiles in the fourth
census (feature-nodisx-linux-gpu-drivers-built-by-pxx), because every
LinuxKPI kmalloc reaches it.

Minimal: `#define Z 0x100` / `#define f(a) (f((a) & ~Z) + 1)`, then `f(0x101)`.

Fix (compiler/cpreproc.inc, CPExpandRange): a painted function-like name
appends #1 and the name, and scanning resumes right after the name.
Test row c_paintq26.
