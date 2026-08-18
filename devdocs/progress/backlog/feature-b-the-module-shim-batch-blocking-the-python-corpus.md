---
track: B
prio: 62
type: feature
owner: unassigned
blocked-by: []
summary: "The missing-module shims are the single largest lever on the third-party Python corpus, and until now they had no ranked ticket — the measurement lived only inside a META ticket parked in unfinished/, invisible to ready/next. Re-measure first: every count below is a dated snapshot."
---

# The module-shim batch blocking the Python corpus

## Why this ticket exists at all

The work was **measured across four separate ladder scans and never filed.** The
numbers lived inside
[[feature-nilpy-thirdparty-libraries-as-targets]] — a META ticket sitting in
`unfinished/`, which `ready`/`next` do not read. So the largest lever on the
corpus could not be ranked, claimed, or dispatched, and each scan re-derived the
same table instead of the work being queued once.

That META ticket's own conclusion is the mandate here:

> Everything blocking the ladder now is a missing MODULE except five files. That
> is Track B shim work, not Track N language work — so the honest read is that
> **Track N is no longer the bottleneck for this ladder.**

Meanwhile `ready --track B` topped out at **p30**. A queue cannot rank what was
never filed. See `feedback_measuring_a_thing_is_not_filing_it`.

## FIRST STEP IS A RE-MEASURE, NOT A SHIM

**Every count below is a dated SNAPSHOT and must not be treated as current.** The
table was taken 2026-08-14 at sha `c61b43390`, and a great deal has landed since
— including four Track N fixes on 2026-08-18 (builtin subclassing, the two-arg
super, the from-import binding fix, the shim-class visibility fix), each of which
can move files past walls that this table still shows as blocking.

The parent ticket records exactly this hazard biting before: two scans disagreed
because the pin moved underneath one of them. So:

```
tools/nilpy_ladder.py     # re-run, note the sha of the compiler binary used
```

Report **past-a-wall separately from onto-the-next-wall** — the corpus compile
count sat at 6/48 through a day in which a great deal genuinely moved, and
conflating the two misreads the campaign in both directions.

## The snapshot (2026-08-14, sha c61b43390 — RE-MEASURE BEFORE USING)

| missing module | files blocked |
| --- | --- |
| `six` | 13 |
| `webencodings` | 6 |
| `warnings` | 3 |
| `xml_dom` | 3 |
| `genshi_core` | 2 |
| `xml_sax_xmlreader` | 2 |
| `codecs` | 2 |
| `_utils`, `constants`, `colorsys`, `urllib_request` | 1 each |

`six` was measured directly against pip's vendored `six.py` (998 lines): it clears
its whole language surface and stops at line 25, `import functools`. As of that
scan it is **purely a shim job** — the language blocker it used to have shipped.

## Known sequencing trap

`html5lib/_utils.py` was ranked up as a chokepoint on the strength of a
first-wall table, and **does not move at all** — it stops on
`no unit named xml_etree_elementtree` long before reaching the `MethodDispatcher(dict)`
wall that the rerank was about. A first-wall table structurally cannot see what
sits behind the wall, so **count users, not first walls**, and expect levers to
compound rather than to pay out in sequence.

## The scope question that must NOT be answered by assumption

Several of these rows are XML (`xml_dom`, `xml_sax_xmlreader`, and the
ElementTree row behind `_utils.py`). Whether pxx wants a **thin shim** or a
**real XML implementation** is a genuine fork with long consequences, and
[[feature-b-a-real-minidom-is-an-implementation-not-a-shim]] already frames one
half of it.

**If the answer for any row is anything other than a thin shim, file a `decide-*`
Track U ticket rather than absorbing the assumption into this job.** This ticket
covers thin shims; it does not authorise writing an XML library.

## Gate

Track B: build with `$(PXX_STABLE)`, never rebuild the compiler. `make lib-test`
green. A compiler or frontend gap found while shimming → file it in the owning
lane (Track N for language, A for core), do not fix it here.
