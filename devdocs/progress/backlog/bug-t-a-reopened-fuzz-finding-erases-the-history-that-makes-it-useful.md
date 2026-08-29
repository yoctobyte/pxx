---
slug: bug-t-a-reopened-fuzz-finding-erases-the-history-that-makes-it-useful
title: "A reopened fuzz finding overwrites first_seed/first_sha/opened and DELETES fixed/fixed_sha - the reopen flag survives, the facts about it do not"
track: T
type: bug
prio: 45
blocked-by: []
status: backlog
found: 2026-08-29
found-by: frank-coordinator
---

# A reopened fuzz finding erases the history that makes it useful

- **Type:** bug (Track T - the fuzz ledger, `devdocs/progress/tstate/fuzz/LEDGER.json`)
- **Found:** 2026-08-29, reading `ec2f50d8c` during a coordinator tick.
- **Severity:** the instance is harmless; **the mechanism is not.**

## Measured - the same entry, before and after one reopen

`fpc-self_if` was found on borg 2026-07-14, marked fixed 2026-08-16, and
re-appeared on plexus 2026-08-29. Diffing its ledger entry across that reopen:

| field | before the reopen | after | |
| --- | --- | --- | --- |
| `first_seed` | `27295` | `91108` | **overwritten** |
| `first_sha` | `dbbcc912715f` | `eb1b200ee92f` | **overwritten** |
| `opened` | `2026-07-14T17:41:07Z` | `2026-08-29T03:54:33Z` | **overwritten** |
| `fixed` | `2026-08-16T12:05:05Z` | *absent* | **deleted** |
| `fixed_sha` | `42e147157b60` | *absent* | **deleted** |
| `hits` | `1` | `1` | not incremented |
| `examples` | `[(27295, dbbcc912715f)]` | `[(91108, eb1b200ee92f)]` | **replaced** |
| `reopened_from_fixed` | `False` | `True` | the one honest field |

So after a reopen, **`first_*` does not mean first** - it means *first since the
most recent reopen* - and `opened` does not mean opened. Nothing in the entry says
so.

## Why this is the expensive shape and not a tidiness complaint

`reopened_from_fixed: True` records **that** the event happened and destroys
**every fact about it.** A flag that survives while its evidence is deleted is
worse than no flag: it tells a reader there is a history and gives them nothing to
read, so the natural next step - "when was it fixed, and what reopened it?" - has
no answer in the file that just claimed the event.

The concrete loss here is a **bisect bracket.** `fixed_sha=42e147157b60` and the
reopening sha `eb1b200ee92f` together bound the window in which the finding came
back. That pair is exactly what a regression hunt starts from, and the ledger held
both, one at a time, and now holds neither.

**This instance is harmless and that is the trap.** `fpc-self_if` is FPC
contradicting itself between `-O0` and `-O2`; the note says so and pxx agrees with
`fpc-O0` at all three levels, so *"pxx is not involved"* and no bisect was ever
wanted. **The erasure is generic - it will behave identically on a pxx-side
finding**, where the bracket is the whole value. The mechanism was observed on the
one class of finding whose loss costs nothing, which is why it has survived since
at least the 2026-07-14 entry.

Related, and probably the same fix: the commit subject reads **`NEW: fpc-self_if`**
for a signature the ledger itself knows is a reopen. `NEW` is a word people grep
for and act on. A reopen is arguably more interesting than a first sighting - it
means something that was fixed came back - and it is currently reported in the
vocabulary of a first sighting.

## Direction

Preserve on reopen rather than replace: keep `first_seed`/`first_sha`/`opened` as
the **original** discovery, append to `examples` instead of replacing, increment
`hits`, and retain `fixed`/`fixed_sha` as history (a `reopens: [{fixed_sha,
reopened_sha, at}]` list keeps the bracket explicit). Then say `REOPENED` rather
than `NEW` in the subject line when `reopened_from_fixed` is set.

**Not measured, and worth one check before building:** whether any *other* ledger
transition overwrites the same way - this was found by diffing one entry across
one reopen, and the fix should be chosen after looking at the writer, not
generalised from this row. **Look for an existing preserve path before adding
one** - the ledger already carries a `fixed`/`fixed_sha` pair it knows how to
write, so the machinery may be present and simply not reached on this edge.

## Gate

Track T's own quick tier, per the per-fix loop in CLAUDE.md - do not widen it.
Plus a guard that drives one signature through open, then fixed, then reopen over
a scratch ledger and asserts the original discovery survives. **That guard must
fail against today writer before it is believed** - a guard that passes on the
unfixed code is measuring nothing.
