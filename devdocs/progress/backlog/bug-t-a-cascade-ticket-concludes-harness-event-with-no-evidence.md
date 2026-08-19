---
slug: bug-t-a-cascade-ticket-concludes-harness-event-with-no-evidence
track: T
type: bug
prio: 45
status: backlog
blocked-by: []
summary: "file_cascade_ticket's Root-cause-suspects line falls back to 'likely a broken build or harness event' whenever no CASCADE_ROOT_JOBS entry is in the red set. That is a conclusion drawn from the absence of one narrow signal, printed with no hedge, and it is now directly contradicted by the Range section shipped in 8ec77190c — which on the live incident named the actual cause. Same defect class the Range work fixed for the sha: an auto-filed ticket asserting something it has no evidence for."
---

# A cascade ticket concludes "harness event" with no evidence for it

## The finding

`file_cascade_ticket` renders a **Root-cause suspects** line:

```python
", ".join("`%s`" % r for r in roots) if roots
else "none of the known root jobs — likely a broken build or harness event"
```

`roots` is `new_red` filtered against `CASCADE_ROOT_JOBS` — a short curated list
of jobs known to take many others down with them. So the fallback fires whenever
none of *those specific jobs* is red, and it converts that single narrow
absence into a positive claim about the cause.

**The first clause is true and useful.** "None of the known root jobs" is a fact
about the red set. **The second clause is invented.** Nothing in the filing path
looked at the build, the harness, the box, or the range before writing "likely a
broken build or harness event".

## Why it matters more now than it did yesterday

`8ec77190c` added a Range section that lists the commits in the range touching a
buildable file. On the live incident (`regression-cascade-4e27dc2be114`) the two
sections sit adjacent and disagree:

- Root-cause suspects: *"none of the known root jobs — likely a broken build or
  harness event"*
- Range: three buildable commits, one of them
  `e1109d7bcbf9 feat(A,N): a bare NilPy import resolves to Python, not a Pascal unit`
  — which **was** the cause.

A reader who trusts the first line stops looking. That is worse than the state
before the Range section existed, because the ticket now contains its own
refutation and gives no reason to prefer one half over the other.

This is the same defect class the Range work fixed one section lower: an
auto-filed ticket stating a confident conclusion it has no evidence for. Face 1
publishes **signal, not judgment** (`twatch.py` header: *"No AI, no judgment:
signal only"*), and this line is judgment.

## Shape

Say what was checked and stop:

> **Root-cause suspects in the red set:** none of the known root jobs
> (`CASCADE_ROOT_JOBS`). That is the only heuristic applied here — it does not
> imply a harness event; see the Range section for commits worth checking.

If a positive claim about a harness event is wanted, it has to be earned from
something the run actually observed — a build failure, a reseed, an infra
marker, `st["infra"]` — not from the absence of an entry in a curated list.

## Gate

`tools/twatch_cascade_range_devtest.py` extended with a case asserting the
suspects line makes no causal claim when `roots` is empty; `make tools-devtest`.

*Filed by Track T (plexus-T) 2026-08-19, after shipping the Range fix next to
it and declining to grow that ticket.*
