---
slug: bug-t-the-full-matrix-switches-itself-off-when-the-fleet-is-busy
type: bug
track: T
prio: 60
status: open
owner: frankH
---

## summary

The full tier's breadth is starved when TESTABLE commits arrive closer together
than **`native_wall + full_commit_secs` (~230s)** — and above that rate breadth
degrades **silently**, because the native tier keeps publishing green.

**CORRECTED 2026-09-06, and the first version of this ticket had the wrong
population.** It said "one push per 60 seconds", counting ALL commits. The code
does not count all commits: `needs_test()` (twatch.py:6612) returns False for a
commit whose every path is under `NOTEST_PREFIXES = ("devdocs/", "docs/")`, and
the abort check is `any(needs_test(...) for c in commits_between(...))`. Since
18:37Z, 50 of 69 commits were docs-only — **72% of the traffic is free.**
Corrected by frankuser and frank-coordinator; the raw-commit correlation was
real and fitted the outage perfectly, and it fitted because docs traffic and
code traffic are produced by the same seats and move together. **A correlation
measured over a superset tracks the subset whenever the two move together**,
which is why the check has to be against what the code counts, never against
the quality of the fit.

## the mechanism, measured 2026-09-06

`twatch.py`'s phase ladder is priority-ordered and step 1 (new push -> fast
tier) preempts everything below. The idle full backfill has a commitment point,
`full_commit_secs = 60` (`CONF_DEFAULTS`, used at the backfill and at the
request queue): a push inside the first 60s aborts the run and it publishes
nothing; after 60s it is allowed to finish. So a full needs **60 contiguous
push-free seconds to become uninterruptible.**

**THE TERM BOTH CORRECTIONS MISSED: the native verdict must finish first.** A
full is an IDLE-cycle phase, and the box is not idle while it is running the
fast native verdict for the newest sha — ~170s wall, measured. So a full does
not need 60 quiet seconds; it needs the native to complete AND THEN 60 seconds,
i.e. a testable gap of roughly `170 + 60 = 230s`.

Gaps between consecutive TESTABLE commits since the last published full:

```
  all 18 gaps >= 60s :  11   [68, 92, 108, 124, 130, 135, 140, 162, 191, 256, 416]
  ... but >= 230s    :   2   [256, 416]
```

So the run had **two** opportunities in forty minutes, not eleven, and the
longer of the two leaves 186s of margin while the shorter leaves 26s. Zero
published fulls is what that distribution predicts. The eleven-gap count is what
made "sixty seconds" look refuted; the two-gap count is the one the mechanism
acts on.

The pre-18:37 fulls were COMPLETE, not truncated — `timed_out: False`,
`unreached: 0`, deadline 4547s never approached. They read ~601s because
partial-resume carries decided jobs forward; the cold cost is 1867s (the
16:16:30Z run). A commit touching `compiler/**` invalidates the partial
(`load_resume()` keeps it only if the compiler rebuilds byte-identical), so a
busy fleet also raises the price of each attempt.

## the "never STARTED" alternative is refuted, not merely untested

It was proposed that `idle_phase`'s ladder restarts at the bottom on every
testable push and, with the shipped default collapsing mid and deep to `full`,
the daemon might never REACH the full rung — a different failure, since a full
never started and one started-then-aborted are indistinguishable in the archive.

The code settles it against that reading. `idle_phase` is:

```python
lf = st.get("last_full") or {}
if lf.get("sha") != tested:        return mid_tier     # == "full" by default
if mid_tier != deep_tier and lf.get("tier") != deep_tier:  return deep_tier
return None
```

Under `mid_tier == deep_tier == "full"` the FIRST idle rung already returns
`full`; there is no two-step climb to be interrupted before reaching it. The
collapse that was thought to hide the rung is what makes it immediate. So the
archive's silence is started-and-aborted, which is what a commitment window
describes.

## why it is not just "ask for one"

The request queue (`--request <sha> --request-tier full`) is drained FIRST among
idle phases and is the documented escape hatch — but it carries the **same 60s
commitment requirement**, so it jumps the queue without escaping the starvation.
`twatch.py` records exactly this, 2026-08-27: *"a `full` request sat undrained
while the log showed the phase being ENTERED and then 'preempted by a push —
will resume', 15 times. The queue's position was never the problem — it is
reached fine and cannot FINISH."*

## why this is a decision and not a patch

Every piece behaves as designed and the design is documented and reasoned. What
is new is FLEET SIZE: enough concurrent workers and the repo never goes quiet
for 60s, so the fleet switches off its own cross-target coverage by working
normally, and nothing reports that it has.

CLAUDE.md's breadth guarantee — *"T samples the tip every ~8 commits, a
persistent regression is caught within ~8"* — is being satisfied by the NATIVE
tier while the full matrix falls behind. Those are different claims and the
rule does not distinguish them.

Options, none taken: raise `full_commit_secs`; reserve a periodic full slot that
pushes may not preempt; make breadth age a reported signal that goes RED on its
own; or accept it and treat a landing hold as the standing procedure before any
tier that matters. **The last is what worked on 2026-09-06** — but it needs a
human to call it, which is the part that does not scale.

## not claimed

Measured on seven, on one day, at one fleet size. The threshold is derived from
`full_commit_secs` and the observed push rate, not from an experiment that
varied the rate.
