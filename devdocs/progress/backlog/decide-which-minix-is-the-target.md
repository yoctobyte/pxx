---
track: U
prio: 58
type: decide
blocked-by: []
summary: "MINIX 2 / early 3.1.x (small, plain, ACK-era C) versus MINIX 3.2+ (which imported the NetBSD userland and build system). These are close to different projects for our purposes, and the choice dominates the cost of the whole lighthouse. Recommendation: MINIX 2 / early 3.1.x."
---

# Decide: which MINIX is the target?

Gates [[goal-compile-minix]]. **Must be answered before any work starts**, because
whoever starts will otherwise settle it by accident — and the two options differ
by more than effort.

## The fork

**Option A — MINIX 2 / early 3.1.x.** Small (~15k lines), plain, ACK-era C.
Assembly lives in separate `.s` files, which is the property the entire
"MINIX before Linux" argument rests on. Bounded, with a crisp binary win
condition (it boots or it does not).

- *For:* maximises the one advantage over the Linux dot. Bounded scope. Exercises
  a genuinely new conformance surface (pre-ANSI C, `_PROTOTYPE` macros, K&R-style
  definitions) that none of our modern-C corpora touch.
- *Against:* it is a historical system. Compiling it proves conformance against
  1990s C rather than anything contemporary, and the bug harvest may skew toward
  constructs nobody writes today.

**Option B — MINIX 3.2+.** Imported the **NetBSD userland and build system**
(`build.sh` / `nbmake`).

- *For:* a live system, modern C, and the NetBSD userland is itself an enormous
  and valuable C corpus — arguably a bigger bug harvest than the kernel.
- *Against:* a large tooling surface full of NetBSD-isms. Risks re-importing
  exactly the "depends on way more tooling" problem that the `CC=` decision was
  supposed to sidestep, except here it is the *build system*, not the compiler
  driver. Scope stops being bounded.

## Recommendation

**Option A.** The reason to do MINIX at all is that it is the rung below the
Linux dot — bounded, inline-asm-light, i386-native. Option B trades that away for
corpus size we can pursue separately and more cheaply: **if the NetBSD userland
is the prize, it is its own corpus ticket and does not need to arrive attached to
an OS boot goal.** Keep the lighthouse bounded; harvest NetBSD on its own terms.

## What the answer changes immediately

- Which source tree gets vendored and probed first.
- Whether pre-ANSI C support becomes a real Track C workstream (Option A) or is
  not needed at all (Option B).
- Whether the build story is "`CC=pxx` plus GNU as/ld" (A) or "`CC=pxx` inside
  nbmake" (B), which is a materially larger integration.
