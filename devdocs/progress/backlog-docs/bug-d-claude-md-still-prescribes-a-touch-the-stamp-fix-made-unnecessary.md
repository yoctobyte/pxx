---
slug: bug-d-claude-md-still-prescribes-a-touch-the-stamp-fix-made-unnecessary
track: D
prio: 45
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "CLAUDE.md's per-fix-loop section tells readers to `touch` the sources after seeding a tree from outside, because a copied-in binary's mtime made `make compiler/pascal26` a no-op that exits 0. The $(COMPILER_STAMP) mechanism closed that hole; measured 2026-08-30, a cp'd seed newer than every source still builds and converges. The instruction is now cargo, and it sits in the one section that is the single source of truth for gating."
---

# D: CLAUDE.md still prescribes the `touch` that the stamp fix made unnecessary

**Owner's file — flagged, not edited.** CLAUDE.md's gating section is the single
source of truth for the per-fix loop and no agent rewrites it on its own
initiative. This ticket exists so the correction is not lost.

## The stale instruction

CLAUDE.md, "THE PER-FIX LOOP", after describing the copied-in-seed no-op:

> **So when you seed a tree from outside, `touch` the sources after the copy (or
> `touch -d '2000-01-01'` the seed), and do not accept the build until you have
> seen `converged after N round(s)` and confirmed the binary's sha256 differs
> from `pinned`.**

The first clause is no longer true. The rest of the sentence still is, and
should stay.

## The measurement

The hole it describes was real: `cp` stamps the seed newer than every source, so
make declared the target up to date and printed
`make: 'compiler/pascal26' is up to date.` where `converged after N round(s)`
belonged — a success message in the wrong dialect, with no error to wait for.

`bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources`
closed it by moving the recipe onto `$(COMPILER_STAMP)`
(`compiler/.pascal26.fixedpoint`), which a `cp` cannot create. Verified
2026-08-30 on plexus:

```
$ cp stable_linux_amd64/default/pinned compiler/pascal26   # seed now newest
$ rm -f compiler/.pascal26.fixedpoint
$ ls -l --time-style=+%s compiler/pascal26 compiler/compiler.pas
  1788082622 compiler/pascal26        <- newer
  1788078221 compiler/compiler.pas
$ make compiler/pascal26
  converged after 2 round(s)
  self-host fixedpoint: verified — 2 round(s), 6319b892f517
```

The build ran, and the stamp guard also catches the opposite case: replacing the
binary without rebuilding now fails with *"Something replaced the binary without
rebuilding"* rather than passing silently.

## Why this is worth a ticket rather than a shrug

The instruction is harmless to follow and that is exactly the problem — it will
never be discovered by failing. It costs a reader nothing to do and costs the
next author of a seeding script the belief that mtime still matters, in the one
section other docs are told to defer to. **A defensive step that no longer
defends anything is indistinguishable from one that does, until someone
measures.**

Found while rewriting the Makefile's seed-missing message
([[decide-forwardlint-in-the-per-fix-loop]]'s resolution): the message was about
to repeat the same advice, and checking first is what turned it up.

## The fix

Strike the `touch` clause; keep *"do not accept the build until you have seen
`converged after N round(s)` and confirmed the binary's sha256 differs from
`pinned`"*, which is still exactly right and is the load-bearing half. A
sentence on the stamp replacing the mtime dependency would be worth one line —
readers who learned the old rule need to know why it went.

## Gate

Docs only. The claim is already measured above; re-run those five lines if it
needs re-confirming.
