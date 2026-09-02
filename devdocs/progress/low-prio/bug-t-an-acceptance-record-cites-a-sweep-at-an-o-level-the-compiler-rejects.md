---
track: T
prio: 55
type: bug
status: low-prio
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "The tkShrLogical rename (314481dd7) records its acceptance as 'byte-identity of emitted output on seven targets at -O0..-O4', in both LOGBOOK.md and BOARD-done.md. The compiler answers `unknown option: -O4` and compiler.pas:1034 accepts -O0/-O1/-O2/-O3 only; `git log -S` shows it has NEVER accepted -O4. So the acceptance cites a level that cannot have been swept. Whatever produced that sweep either skipped the level silently or errored without failing the claim — either way 'we did not measure it' was recorded as 'we measured it and it was fine'."
---

# An acceptance record cites a sweep at an O-level the compiler rejects

## The claim

`devdocs/progress/LOGBOOK.md:283` and `BOARD-done.md:339`, both for the
`tkShrLogical` rename `314481dd7`:

> *"the rename's acceptance was **byte-identity of emitted output on seven
> targets at -O0..-O4**"*

## The fact

```
$ ./compiler/pascal26 -O4 --help
unknown option: -O4
```

`compiler/compiler.pas:1034`:

```pascal
else if (option = '-O0') or (option = '-O1') or (option = '-O2') or (option = '-O3') then
```

And it has never been otherwise — `git log -S"'-O4'" -- compiler/compiler.pas`
is **empty**.

`-O4` is real as an *intention*: `decide-the-o-level-charter` calls it "the
research tier: correct, but so speculative it may never…", and CLAUDE.md:189
carries it with correctness obligations. It is not a level the compiler has.

## Why this is a defect and not a typo

The range `-O0..-O4` was not decoration; it was the **acceptance evidence** for a
rename that touched 25 sites of a shared IR spelling. One fifth of the stated
sweep could not have run. Either the harness silently skipped the rejected level,
or it errored on it and the error did not fail the claim. Both are the same
defect class this tree names repeatedly:

> *"We did not measure it" must not be recorded as "we measured it and it was
> fine" — that substitution is the defect class this whole gate exists to catch.*
> (`seed_baseline`, tools/twatch.py)

There is a sharp irony worth keeping. That LOGBOOK entry exists to record that
the byte-identity acceptance **was too weak to catch the bug** — "a strong check
that could not see this, because a frontend whose output is not in the corpus
emits no bytes to compare". It was weaker still, in a second and unrelated way,
and the entry written to confess the first weakness carries the second.

## What to do

1. **Find the sweep** that produced the `-O0..-O4` claim and make an unknown
   O-level a hard failure rather than a skip. A sweep that cannot run a level it
   was asked for must not report success for that level.
2. **Correct the two records.** They are in `done/`-adjacent history, so the fix
   is an annotation, not a rewrite: say what was actually swept (`-O0..-O3`).
3. **Decide what `-O4` means in prose.** Not this ticket's call —
   `decide-the-o-level-charter` owns it. But while it reads as a level in
   CLAUDE.md's O-section, references like this one will keep being written by
   people who reasonably believe it exists.

## Scope check already done

`-O4` appears in **no** Track T sweep, gate, or shadow config: `grep -rn -- '-O4'`
over `tools/`, `Makefile`, `.testmgr/` and `trackt` returns exactly one hit, and
it is the prose comment at `Makefile:7667` quoting this same acceptance claim.
So nothing is currently *executing* against a rejected flag; the damage is to
the record, not to a live gate.

Found while checking a report from frank-user that `-O4` might be referenced by
running tooling. It is not — but the claim that led there was wrong in a more
interesting way.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
