---
slug: bug-t-the-documented-build-path-never-enumerates-what-it-needs
title: "Nothing states what a stranger's box must already have — measured from an attempt, not guessed"
track: T
prio: 45
type: bug
status: open
owner: unassigned
created: 2026-09-06
found-by: frank-subcoord (build-from-clean attempt, 2026-09-06)
summary: "FROM AN ATTEMPT, not the backlog. Build-from-clean now WORKS in a container with only git and make -- verified 2026-09-06 in podman/alpine (musl, no bash, no fpc, no gcc): seed from the committed pin, `make compiler/pascal26`, converged in 1 round to the same sha as the host. But git and make were installed BY THE TESTER via apk, so the one step still unmeasured is a box that lacks them, and NOTHING in the repo states the requirement. The prerequisite set is currently folk knowledge: this attempt found bash was assumed and absent (fixed, 79264f396), which is exactly the shape of an unstated dependency -- it did not error usefully, it silently disabled a guard. Wants a stated, TESTED prerequisite list, not a README paragraph nobody runs."
---

# What does a stranger's box actually need?

Attached to `umbrella-a-stranger-can-get-a-working-compiler-from-a-release`
because an attempt broke on it, which is the only way that umbrella grows.

## What IS measured (2026-09-06)

`podman run --rm alpine`, `apk add git make`, nothing else — **no bash, no fpc,
no gcc**, musl libc:

```
git clone <repo> /work && cd /work
cp stable_linux_amd64/default/pinned compiler/pascal26
make compiler/pascal26        ->  converged after 1 round(s), same sha as host
```

`make bootstrap` (the FPC cold start) is also green on the host — fpc 3.2.2,
54.6s, and the result is **byte-identical to the pin-derived binary**. So the
two paths a stranger might take both work today.

## What is NOT measured, and it is the whole ticket

**git and make were installed by the tester.** A box without them is untested,
and more importantly **the requirement is written down nowhere.** There is no
prerequisite list to check a box against, so "what do I need" is answered by
running the build and reading whatever breaks.

## Why that is worse than it sounds

This same attempt found `tools/compiler_srchash.sh` assuming **bash**, which was
absent in the container. It did not fail usefully — it printed `env: can't
execute 'bash'`, make carried on, and a correctness guard was silently disabled
(fixed in `79264f396`). That is the failure mode of an unstated dependency in
this repo: **not a clear "command not found, install X", but a step that quietly
does not happen.** Every unenumerated prerequisite is a candidate for the same
shape, and we have no list to audit.

## What would close it

A prerequisite set that is **tested rather than documented** — a container row
that installs exactly the stated list and nothing more, builds, and fails if the
build needs anything outside it. That makes the list falsifiable, which a README
paragraph is not. It also gives the umbrella a real attempt to break on next
time, instead of a tester's recollection of what they happened to install.

Note the check must assert the build actually RAN and converged, not merely that
`make` exited 0 — a missing interpreter has already been shown to produce a
green exit here.
