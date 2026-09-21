---
slug: feature-b-threading-condition-is-absent-and-the-corpus-that-justified-omitting-it-has-moved
title: threading.Condition is absent, and the corpus that justified omitting it has moved
summary: "`threading.Condition` is not implemented and `lib/rtl/mimic_threading.pas:55` says so in its own words, in a `## What is NOT here` list alongside Semaphore, Barrier, local, current_thread, active_count, Timer and Thread subclassing. THE OMISSION WAS REASONED AND THE REASON HAS EXPIRED: that paragraph justifies itself with *\"None is used by the corpus this was measured against, and each would be a claim with no test behind it\"* -- which was a good reason and is now false for exactly one member of the list. TSP uses Condition at TWO sites, `tsp/voice.py:79` and `:158`, and needs THREE pieces of surface, not one: construction, `notify()` (:96, :169) and `wait()` (:131, :191), plus the CONTEXT-MANAGER protocol, since every use is `with self._cv:`. A Condition that is constructible but not a context manager fails these call sites as completely as no Condition at all. REPORTED BY frankz-e5 off the TSP wall survey as one site behind at least three board rows; re-verified here in TSP's source rather than on report, which is how the second site and the `with` requirement turned up. RECORDED NOWHERE REACHABLE UNTIL NOW -- it was mentioned only inside a CLOSED `wave` ticket, which is the least likely place in the tree for anyone to look, and that is why it is a ticket rather than a logbook line. INDEPENDENT OF THE OPEN DECIDE, and say so when working it: `decide-should-a-python-program-that-imports-threading-compile-as-written` (p55) asks whether `import threading` should stop being a hard refusal without `--threadsafe`. This gap survives EITHER answer -- a program that passes `--threadsafe` today still fails on Condition -- so this ticket must not be worked in a way that pre-empts that decision, and must not be treated as blocked by it either. WHAT RETIRES THIS: Condition constructible, usable as a context manager, with wait/notify, and `tsp/voice.py` compiling past both sites. The rest of the `What is NOT here` list stays out of scope on its own stated reasoning until a named consumer appears for it too -- the point here is the expired premise for ONE member, not that the list is wrong."
track: B
type: feature
prio: 50
status: backlog
owner: ""
blocked-by: []
created: 2026-09-21
found-by: frankz-e5
---

# threading.Condition is absent

## The omission was deliberate and the reasoning is quoted

`lib/rtl/mimic_threading.pas`, in its own header:

> ## What is NOT here
>
> No `Condition`, `Semaphore`, `Barrier`, `local`, `current_thread`,
> `active_count`, `Timer`, or `Thread` subclassing with an `Execute`/`run`
> override. **None is used by the corpus this was measured against, and each
> would be a claim with no test behind it.**

That is the right way to scope a mimic module, and the emphasised sentence is
the part that has gone stale — **for one member of the list only.**

## The counterexample, with its sites

    tsp/voice.py:79    self._cv = threading.Condition()
    tsp/voice.py:96        self._cv.notify()
    tsp/voice.py:131           self._cv.wait()
    tsp/voice.py:158   self._cv = threading.Condition()
    tsp/voice.py:169       self._cv.notify()
    tsp/voice.py:191           self._cv.wait()

**Two sites, not one**, and every use is inside `with self._cv:` — so the
context-manager protocol is a third requirement beside construction and
wait/notify. A `Condition` that constructs but does not support `with` fails
these call sites exactly as completely as no `Condition` at all, which is the
kind of partial delivery that reads as progress and moves no unit.

## Do not let this pre-empt the decide, and do not let it block on it

`decide-should-a-python-program-that-imports-threading-compile-as-written`
(p55, Track U) asks whether `import threading` should compile without
`--threadsafe`. **This gap is orthogonal:** the module is importable today with
the flag, and a program that passes it still fails on `Condition`. So the
answer to the decide changes WHO hits this and not WHETHER it is missing.

Name that relationship in the resolution, because the two tickets are easy to
read as one — and the failure mode runs in both directions: working this as if
it settled the decide, or parking it as blocked by a question that does not
gate it.

## Scope

One member of a list of eight. The others stay out on the unit's own stated
reasoning — no named consumer, and a claim with no test behind it is worse than
an honest absence. **The finding here is an expired premise for `Condition`,
not that the list was wrong.**
