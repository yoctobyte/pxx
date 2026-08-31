---
slug: umbrella-compile-and-run-dosbox
title: "Compile DOSBox with pxx, for a target, and run it"
track: C
prio: 90
type: umbrella
blocked-by: [feature-c-corpus-busybox-multi-applet]
created: 2026-08-31
summary: "GOAL, not a unit of work. The flagship real-program proof: a large real C/C++ codebase that either builds and runs or does not, with no partial credit to award ourselves. Owner named it first when stating the goal. Attach whatever the ATTEMPT breaks on -- do not pre-populate this from the backlog by guessing."
---

# Compile DOSBox, for a target, and run it

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

Full goal: `devdocs/dev/the-goal-cross-cross.md`.
