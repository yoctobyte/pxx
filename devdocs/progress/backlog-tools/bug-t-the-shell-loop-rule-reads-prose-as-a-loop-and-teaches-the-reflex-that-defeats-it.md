---
track: T
prio: 40
type: bug
status: backlog
found: 2026-09-04
found-by: frankZ
owner: ""
blocked-by: []
summary: "no-full-suite.sh rule 3 fires when a command contains BOTH a `test/*.pas`-shaped string and the bare word `for` — and both conditions are met by a python heredoc iterating in memory, and by a heredoc WRITING A TICKET whose prose happens to say `test/*.pas` and `for`. Hit twice in one session while doing neither. The same file already recognises this class and fixed it for rule 2c ('reading about the rule, not running it, and refusing that is pure noise — the first thing this rule did on the day it landed'); rule 3 did not get the treatment. The cost is not the retry: the documented escape is PXX_ALLOW_FULL_SUITE=1, so the lesson a agent learns is to prefix it reflexively, which is exactly how a guardrail the owner asked for twice stops guarding."
---

# The shell-loop rule reads prose as a loop, and teaches the reflex that defeats it

## What fires

`.claude/hooks/no-full-suite.sh` rule 3 denies when **both** hold:

```
grep -Eq '(test|tests)/[A-Za-z0-9_]*\*[A-Za-z0-9_]*\.(npy|pas|c|py|zig|rs)'
grep -Eq '(^|[;&|(]|[[:space:]])(for|while|xargs|parallel)([[:space:]]|$)|find[[:space:]]+.*-exec'
```

Neither is anchored to a command position. Measured 2026-09-04, two denials in
one session, neither of them a suite run:

1. **A python heredoc doing a text census.** `for i, ln in enumerate(...)` is a
   `for` at a word boundary and the scan named `test/*.pas`. It reads files and
   compiles nothing — about a second.
2. **A heredoc writing a TICKET.** The prose said `test/*.pas` (naming the
   population it had measured) and, elsewhere, "for a wide margin". Writing a
   markdown file was refused as a regression sweep.

The first denial that session was a genuine compile sweep and the rule was
right about it. That is the part worth keeping.

## Why it is worth fixing rather than living with

The escape is documented and autonomous, so the cost is not the retry — it is
what the retry teaches. `PXX_ALLOW_FULL_SUITE=1` in front of everything is a
one-token habit, and an agent that acquires it stops reading the denial. The
owner asked for this guard after repeated incidents; a guard routed around by
reflex is not guarding.

CLAUDE.md is explicit that the answer is never to reshape the command to slip
past — so the honest options are to fix the rule or to keep paying, and paying
is what conditions the reflex.

## The precedent is in the same file

Rule 2c carries exactly this fix and says why: matched at a COMMAND position
only, because *"`grep -n "testmgr.py --pin" CLAUDE.md` is reading about the
rule, not running it, and refusing that is pure noise — the first thing this
rule did on the day it landed."* Rule 3 was written without it.

## Shape of a fix — not decided

Anchoring the loop keyword to a command position (`(^|[;&|(]|&&|\|\|)` as 2c
does, dropping the bare `[[:space:]]` alternative) kills both false positives,
because a python `for` and a prose `for` are both mid-line. It also weakens the
rule against a genuine `cmd && for f in test/*.pas`, which the anchor set would
still catch via `&&`.

Whoever takes it wants a POSITIVE CONTROL from the real population: the
`for f in $(grep -rl TMethod test/*.pas)` compile sweep that was correctly
denied that same session must still be denied. A narrowed guard that stops
catching the thing it was written for is worse than the noise.
