---
slug: umbrella-compile-and-run-dosbox
title: "Compile DOSBox with pxx, for a target, and run it"
track: C
prio: 50
type: umbrella
blocked-by: [feature-c-corpus-busybox-multi-applet, bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]
created: 2026-08-31
summary: "GOAL, not a unit of work. The flagship real-program proof: a large real C/C++ codebase that either builds and runs or does not, with no partial credit to award ourselves. Owner named it first when stating the goal. Attach whatever the ATTEMPT breaks on -- do not pre-populate this from the backlog by guessing."
---

# Compile DOSBox, for a target, and run it

> **PRIO 90 -> 50, OWNER, 2026-09-02.** *"dosbox is real, but not high prio.
> busybox had a high prio."* The goal is unchanged — DOSBox remains a flagship
> proof in `the-goal-cross-cross.md` and this umbrella stays. Only its rank moved.
>
> **Lowering it costs nothing right now, which is why it was safe to do.** Both
> blockers — `feature-c-corpus-busybox-multi-applet` and
> `bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong`
> — are in `done/`, so this umbrella ranks **zero** tickets. The busybox work
> ranks on its own numbers (80 / 70 / 65), not by inheritance from here.
>
> **And that empty chain is the real finding.** It is why DOSBox *looked* like
> the top priority: an umbrella with nothing under it sits at the head of `ready`
> and ranks no work at all. Per CLAUDE.md an umbrella with no blockers means
> **nobody has attempted that cell** — that is information, not missing
> paperwork. Both original blockers were cleared and no one has since tried to
> build DOSBox to find the next one.
>
> **To restore its rank, ATTEMPT THE TARGET** — do not re-populate this from the
> backlog. Each failure names the next blocker in the order it actually matters.

The owner's first-named proof (2026-08-31): *"compiling dosbox or minix 2 or
minix 3 has a prio. And very much prio above hunting a float insignificant bit
issue."*

## Why this one is the flagship

It is **large, real, and binary-valued.** A suite can be green while the product
is useless; DOSBox either runs or it does not. That makes it immune to the
failure that produced a 400-ticket backlog — accurate work that nobody could
rank, because nothing said what on-target meant.

## How to grow this umbrella — attempt, do not triage

**Do NOT populate `blocked-by` by reading the backlog and guessing what DOSBox
might need.** That is the estimate this whole scheme replaces. Go and try to
compile it; each failure names a ticket, in the order it actually matters, and
that ticket gets wired here. What the attempt never touches was, by
construction, not blocking real-world usage.

The one blocker listed today is the rung below: busybox multi-applet is real C
at a smaller scale, already ticketed, and failing it means DOSBox is out of
reach.

**Wired 2026-09-01 by the attempt, not by triage:**
[[bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong]].
Compiling busybox's 52 sources as SEPARATE OBJECTS -- its own build model, and
the only model a project of DOSBox's size has -- ran into it: a pxx object
emits no data symbols at all, so two objects sharing a global link cleanly and
read different memory. Measured, not inferred: the pair prints `0` where gcc
prints `99`, with no diagnostic from the compiler or the linker.

That is the wall for DOSBox specifically. A unity build is what got busybox
`cat` and `cat`+`echo` through, and it does NOT scale -- at seven applets gcc
itself refuses the unity, because each busybox applet defines its own `struct
globals` and `common_bufsiz.h` redeclares its enum. The unity was a way past
the missing capability at small scale; it stops being one well below DOSBox.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.
