---
track: B
prio: 62
type: feature
owner: frank3-fc
blocked-by: [decide-xml-etree-thin-tree-model-or-a-real-xml-library]
summary: "RE-MEASURED on pinned v352: the batch this ticket was filed to attack no longer exists — six, warnings, codecs, colorsys, copy, bisect, xml.sax.*, urllib.parse, six.moves, urllib.request and xml.dom all shipped during 2026-08-18 and are gated by make lib-test. Eight missing-module files remain and none is a thin stdlib shim: xml.etree (4, now a Track U decision), genshi_core (2) and lxml (1) are third-party packages, weakref (1) is a runtime facility. The language walls are 32, with yield alone at 18 — Track N is the bottleneck for this ladder again."
status: unfinished
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

---

## RE-MEASURED 2026-08-18 (frank3-fc) — the premise is stale, and the batch is gone

**Compiler binary: `stable_linux_amd64/default/pinned` = v352, sha
`0d2087d629bf7fc6ebccc0973065b1f51e3a65e2fbe00771aa9081e795af6152`, pin commit
`b14da0847`.** Naming it because this ticket's own instruction is that a count
without a sha is a snapshot, not a measurement.

`tools/nilpy_ladder.py`, three corpora, 48 files, **compile 6/48**.

### The 2026-08-14 table cannot be diffed against this one

Not just stale — a different population. That table lists `six` (13),
`webencodings` (6), `warnings` (3), `codecs` (2), and single rows for
`constants`, `colorsys`, `urllib_request` and `_utils`. Today's ladder scans
`html5lib`, `tinycss2` and `webencodings` — 48 files — and reportlab is present
in `library_candidates/` but is **not** a rung (no `reportlab/reportlab/__init__.py`),
so whatever produced those counts was not this instrument. Row-for-row
comparison would be meaningless; the numbers below replace rather than update
it.

### Every missing-module row that remains — 8 files, none of them a thin stdlib shim

| row | files | what it is |
| --- | --- | --- |
| `xml_etree_elementtree` | 4 | the fenced scope question — now [[decide-xml-etree-thin-tree-model-or-a-real-xml-library]] |
| `genshi_core` | 2 | a third-party package, not stdlib. Shimming it is impersonating a library, and both files are optional backends html5lib guards behind an import |
| `lxml` | 1 | a third-party package, and a C library binding at that |
| `weakref` | 1 | a runtime lifetime facility, not a module surface |

Every row this ticket was filed to attack — `six`, `warnings`, `codecs`,
`colorsys`, `copy`, `bisect`, `xml.sax.*`, `urllib.parse`, `six.moves`,
`urllib.request`, `xml.dom` — **has already shipped**, in
[[feature-b-module-shims-for-the-html5lib-corpus]],
[[feature-nilpy-xml-dom-is-two-questions-not-one]] and
[[feature-b-mimic-six-moves-needs-http-client-and-urllib]], all gated by
`make lib-test`. That is why the batch does not exist any more: it was worked
during the day this ticket's snapshot predates.

### So the mandate quoted at the top no longer holds

> "Everything blocking the ladder now is a missing MODULE except five files …
> Track N is no longer the bottleneck for this ladder."

**Inverted.** Missing modules are 8 files and 4 of them are one decision; the
language walls are 32:

```
18  undefined variable (yield)          <- the entire html5lib filter pipeline
 3  unknown base class Mapping
 3  unknown base class list
 2  no class declares .startDocument()  <- duck-typed call on a handler param
 2  unexpected token                    <- two-arg super(), NOT in the pin yet
 1 each: TMatch.groups, MULTILINE, OrderedDict, lookup, non-UTF-8 source
```

`yield` alone is more than twice every missing-module row combined. **Track N is
the bottleneck for this ladder again**, and Track B's corpus lever is one
Track U decision wide.

### A pin-boundary note, since it changes what the board says

Two-arg `super(Cls, self)` is reported fixed at HEAD, and the two
`unexpected token` files above are html5lib filters waiting on it. It is **not
in v352**, so it is not fixed for Track B and those files have not moved on the
ground B builds on. Measured, not assumed:
`super(B, self).__init__()` → `error: unexpected token` on `pinned` v352.

### Score for this ticket: past a wall 0, onto the next wall 0

Nothing moved, because nothing was written — the re-measure that this ticket
mandates as step one is the deliverable, and it says the batch was already
done. The one remaining candidate is fenced by this ticket's own scope rule and
is now filed as a Track U decision with the measurement attached, so it can be
settled in one read.
