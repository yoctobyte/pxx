---
slug: decide-a-latent-defect-ticket-should-block-the-work-that-makes-it-observable
title: "Should an open ticket describing a latent defect block the work that would make it observable?"
track: U
prio: 55
type: decide
status: new
blocked-by: []
owner: user
summary: "f4fb9d31b made generic constraints load-bearing while bug-p-generic-constraints-are-checked-before-the-type-section-closes sat open at p40 describing exactly why the placement was wrong. The regression was predicted in writing before it happened, and nothing in the board could express the dependency. Same shape hit three times on 2026-08-30. Options: a new edge type, a convention on blocked-by, a check in tools/progress.sh, or accept it."
---

# Should a latent-defect ticket block the work that makes it observable?

Raised by frankwasm, 2026-08-30, from a live instance.

## The instance

`f4fb9d31b` recorded and checked generic constraints for the first time — a
correct and valuable fix; before it, every constraint in the language meant
nothing and all 35 FAIL-marked `tgenconstraint` tests were wrongly *accepted*.

It also broke `test-fgl` on real FPC-corpus code, because
[[bug-p-generic-constraints-are-checked-before-the-type-section-closes]] was
**already open at p40, describing exactly why the placement was wrong.** The
regression was predicted in writing before it happened. Nobody was careless: the
ranker offered the p40 as ordinary low-prio work, `f4fb9d31b` had no reason to
consult it, and no field in a ticket can say *"this becomes a regression the
moment anything reads a constraint."*

## Why it is not just this ticket

Three instances the same day, all the same shape — a mechanism that is inert
because nothing consumes it, and is wrong the instant something does:

- `UFldStrElemTk` hardwired to `Ord(tyChar)` under a comment justifying it as safe
  *today*. Six carriers passed every neutrality test; the first real reader found
  the bug in minutes.
- The seven `not CProgramMode` guards: deleting them changed nothing, which read
  as "not part of the fix" — they were inert *today* and load-bearing the moment
  the prologue was fixed.
- This one.

**The common failure is not insufficient testing.** In all three the *current*
behaviour was correct and fully covered. What was missing was a way to say that a
known-latent defect and the work that activates it are coupled.

## Options

1. **A new edge type** — `activated-by:` / `latent-until:`, so the ranker warns
   when a ticket naming a mechanism is claimed while a latent ticket names the
   same one. Most expressive, most machinery, and it needs someone to *notice* the
   coupling at filing time — which is the same noticing that already failed.
2. **A convention on `blocked-by:`** — point the activating work at the latent
   ticket. Free, but semantically wrong (the activating work is not blocked; it is
   *hazardous*), and it would park genuinely-ready work.
3. **A check in `tools/progress.sh`** — flag when a claimed ticket's `summary`
   shares a distinctive identifier with an open low-prio ticket's. Cheap, no new
   fields, catches this case (`constraint`), and will produce false positives.
4. **Accept it** — treat these as normal regressions, caught by Track T's full
   tier, which is exactly what happened here: seven caught it within the hour and
   the fix is dispatched at p70.

## Recommendation

**(4) with a note, unless the rate rises.** The cost of the miss was one full-tier
red caught the same afternoon; the cost of (1) is a new edge type nobody
maintains, and the noticing it depends on is the noticing that failed. **But (3)
is cheap enough to be worth prototyping** if it can be gated to *claimed* tickets
only, and Track T owns `tools/progress.sh`. Three instances in one day is not yet
a rate, but it is enough to record the shape so the fourth is recognised faster.

The thing worth keeping regardless: **a comment or ticket explaining why something
is safe *today* is a dated claim, and nothing re-checks it when the date passes.**
