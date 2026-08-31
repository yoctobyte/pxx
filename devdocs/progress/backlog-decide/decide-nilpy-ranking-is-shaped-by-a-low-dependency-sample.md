---
slug: decide-nilpy-ranking-is-shaped-by-a-low-dependency-sample
title: "The NilPy campaign's 55-70 mechanism ranking was derived from unusually low-dependency corpora"
track: U
prio: 55
type: decide
blocked-by: []
status: backlog
owner: unassigned
created: 2026-08-28
summary: "A fourth-corpus probe (reportlab 4.2.5, 421 .py) at pin v389 found that NONE of its 30 distinct first walls is a wall the webencodings/html5lib/tinycss2 family produced — because 89% of its failures are missing library surface and it never reaches the mechanism layer. The family's mechanism walls are not wrong, they are CONDITIONAL: they are what a corpus hits once its import surface is already covered. The three corpora that generated the whole 55-70 ranking are self-contained web parsers with almost no stdlib footprint. On a corpus with an ordinary footprint, landing the entire mechanism cluster would move compile count by ~zero. prio: is the human's field, so the re-ranking call is the owner's."
---

# The ranking is shaped by the sample, and the sample is unusual

Measured by frankB under
`feature-b-a-fourth-corpus-to-test-whether-the-ladder-walls-generalise`
(resolved `b125395e2`). reportlab 4.2.5, 421 `.py` / 0 `.c`, run as a separate
probe at pin v389 — md5 `0453ed506a14e464fd6c6cf0d81c6a55`, base `83468c5462d4`,
via a new `--probe=<dir>` mode that reuses the ladder's exact method while
keeping its own baseline and roots. **The `N/48` series is untouched.**

36/159 compile. 123 failures over **30 distinct first walls**, and **not one of
them is a wall the family produced** — nothing from the callable / dispatch /
kwargs / decorator / protocol cluster this campaign ranks 55-70.

**But the reason is not that reportlab hits different mechanisms.**

| share | class |
| --- | --- |
| **89%** (109/123) | **library surface** — 16 of the 17 stdlib modules its top walls name have **no shim at all** (`functools` 27 files, `pickle` 18, `binascii`, `encodings`, `hashlib`, `struct`, `weakref`, …) |
| 6% | syntax |
| 7 files | unclassified, counted neither way |

It stops at its first missing import and **never reaches the mechanism layer.**

## The fork

The three corpora that generated the ranking — webencodings, html5lib, tinycss2 —
are self-contained web parsers with almost no stdlib footprint. That is what such
a library *is*. They arrived at the mechanism layer immediately and have been
producing the ranking ever since.

So the mechanism walls are **conditional**: they are what a corpus hits *once its
import surface is already covered*. On a corpus with an ordinary stdlib
footprint, landing the whole 55-70 cluster moves compile count by **~zero** —
those items sit behind sixteen missing modules.

This is the trap `six` sprang at *file* scale (it gated 15 files; landing
`mimic_six` moved 4/48 → 4/48), now reproduced at **corpus** scale.
**Compile count lags; walls-cleared leads.**

The campaign has **no measurement of library surface at all**. The ticket that
would produce one — `feature-nilpy-stdlib-coverage-gaps-measured` [p72] — is the
**top-ranked NilPy feature in the backlog and has never been started**, while
items below it get worked.

### Options

1. **Measure first, then re-rank** *(recommended)* — start
   `feature-nilpy-stdlib-coverage-gaps-measured` before any further mechanism
   work. It is already top-ranked; the only change is actually taking it. The
   re-ranking question then answers itself with data instead of judgement.
2. **Re-rank the mechanism cluster down now** on this evidence alone. Cheap, but
   it trades one unmeasured ranking for another — and the mechanism walls are
   genuinely real, just gated.
3. **Leave the ranking as-is**, on the view that the low-dependency corpora are
   the *right* sample because mechanism gaps are compiler work and stdlib shims
   are library work with a different owner. Defensible; should be stated
   explicitly if chosen, because it is currently true by accident, not by choice.

**No re-ranking has been done.** `prio:` is the human's field and frankB
correctly did not touch it. Track N is also currently undispatched by owner call,
so nothing is blocked on this today — it is filed so the evidence outlives the
session that measured it.

## Boundary case already split out as a bug

The #1 wall, `undefined variable (os)` at 30 files, is nominally library surface
but is really a **seam**: `os.getcwd()`, `os.path.join()`, `os.getenv()`,
`os.environ.get()` all compile (dotted calls special-cased in `pyparser.inc`),
while `'HOME' in os.environ` and `os.sep` fail — there is no `os` module *value*
behind the special-case (`pyparser.inc:11852` accepts only `seek_set/cur/end`).
One seven-line leaf file, `reportlab/lib/__init__.py`, ending in
`RL_DEBUG = 'RL_DEBUG' in os.environ`, gates all 30.

Filed separately as `bug-n-os-environ-and-os-sep-are-not-values` [N, p60].
Textbook `normalise-dont-special-case`.
