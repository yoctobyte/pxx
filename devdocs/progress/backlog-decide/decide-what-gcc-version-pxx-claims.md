---
slug: decide-what-gcc-version-pxx-claims
track: C
prio: 30
type: decide
status: backlog
created: 2026-11-22
found-by: claude-pxx (micropython v1.24.1 unix port, py/nlrx64.c)
summary: "OWNER DECISION. pxx predefines __GNUC__ 2, __GNUC_MINOR__ 7 so that code gated on gcc 3.x/4.x builtins takes its portable path; cpreproc.inc records the busybox measurement (1 fixed, 0 broken). Some code gates the CORRECT path on a newer gcc. micropython's py/nlrx64.c uses __attribute__((naked)) only when __GNUC__ >= 8, and pxx supports naked now. At 2.7 it takes a fallback (optimize(\"omit-frame-pointer\") plus `jmp` in ordinary inline asm) that pxx cannot compile. The scratch build passes -U__GNUC__ -D__GNUC__=8 for that unit."
---

# Which gcc version should pxx claim?

## The trade

- **Claim 2.7 (today).** Code gated on newer builtins (`__builtin_*`,
  typeof, labels-as-values, `__GNUC_PREREQ(4,5)`) stays on its portable
  arm. Code that picks a *better* path for newer gcc gets the old one.
  Sometimes the old one is worse: nlrx64.c falls back to
  `optimize("omit-frame-pointer")`, which pxx does not honour.
- **Claim something newer, e.g. 8.** Every gated feature becomes
  reachable, and each needs to be supported or refused loudly. Before
  that, measure the busybox, micropython, tcc, toybox and Rainyday corpora
  at the new value.
- **Per-unit override.** The user passes `-U__GNUC__ -D__GNUC__=N`. This
  works since bug-c-command-line-undef-is-applied-after-every-define was
  fixed. It is a build-system choice, not a pxx default.

## Evidence

feature-c-attribute-naked-and-inline-asm-branches-to-symbols (done). With
the override, pxx builds nlrx64.c and micropython passes 897/908 with every
unit built by pxx, the same as with gcc's nlrx64.o.

Not decided by an agent. Don't change the claimed version without the owner.
