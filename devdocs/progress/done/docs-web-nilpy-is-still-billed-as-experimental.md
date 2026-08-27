---
track: W
prio: 55
type: docs
blocked-by: []
summary: "RESOLVED 2026-08-27, verified live at 4beadde. nilpy now reads Supported (fidelity target: CPython observable behaviour), C++ reads Not planned, and the site-wide meta description says 'Pascal, C and Python compiler'. NOTE it was SIX locations, not the four this ticket listed — see the grep lesson below. Originally: the website billed NilPy as experimental in four places — the compliance table says `Experimental`, the frontpage and about say `staged`, and the site-wide meta description says `in development` — while `docs/targets/nil-python.md` in the pxx repo already says the opposite (mainline frontend, peer of Pascal and C, gated by test-nilpy). Owner's call 2026-08-27: Python is a first-class citizen now, open bug tickets notwithstanding. Content files live in the website repo, so this is W by file ownership even though the work is D-shaped. ALSO on the same page, owner 2026-08-27: C++ is billed as `Never` / `deliberately never` — the substance is right and stays, but soften the absolute. Never say never."
status: done
---

# The website still bills NilPy as experimental; the docs already say otherwise

## RESOLVED 2026-08-27 — shipped as `4beadde`, verified from the public internet

Verified by `frank2-af` with a plain `curl`, independently of the origin-side check:

```
<meta name="description" content="PXX is a from-scratch Pascal, C and Python
  compiler — self-hosting, cross-compiling to several CPU targets, highly FPC-
  and C99-compatible, with nilpy compiling Python to native binaries.">
```

| row | status | fidelity target |
| --- | --- | --- |
| nilpy | **Supported** | CPython's **observable behaviour** — divergences filed as bugs |
| C++ | **Not planned** | "No plans to implement — see below" |

`/` and `/about/` carry no remaining `staged` / `in development` / `never`. The
one `out of scope` still on `/compliance/` is the **C row** — "C99 — GCC
extensions out of scope" — which is correct and unrelated.

`ianweb` made the nilpy fidelity claim **harder**, not softer: "Python syntax
only" became CPython observable-behaviour parity with divergences filed as bugs,
lifted from `docs/targets/nil-python.md`. That is the right call and worth
noting — the page had understated the ambition and overstated the limits at the
same time, and it gives the deep NilPy queue its honest reading: an exacting
reference target, not a fragile frontend.

## THE GREP LESSON — it was SIX locations, not four

The table below listed four. There were six. The miss was `about.md:59`, a
footnote under the About page's footnote list, carrying both "Staged —" and a
*second independent copy* of the library-ecosystem claim.

**Why it evaded the sweep:** the four were found by grepping the **wordings
already known** — `experimental|staged|in development`. The sixth phrased the
same claim differently, in prose reachable only through a footnote link.
`ianweb` found it by grepping the **claim-space** across all of
`pxxweb/content/` before editing — `staged|experimental|in development|out of
scope|never` — which cost seconds.

**The rule: grep for the CLAIM, not for the WORDING you already found.** A
string sweep answers "where does this sentence appear", which is a different
question from "where does the site say this thing" — the same
correct-reading-of-the-wrong-instrument shape that cost this lane an afternoon,
in search rather than in measurement. Prose restates; only the claim is
invariant. Corollary: **sweep before editing, not after**, because the cheap
pass is worthless once you have already fixed the instances you knew about.



Owner, 2026-08-27:

> *"on website, subject compliance, we still list nilpy as experimental. i think
> that's no longer fair - python is first class citizen by now, despite the list
> of open bug tickets."*

**Fix lands in the private `~/pxx-website` repo, not this checkout.**

## The four places, measured

| file | line | current text |
| --- | --- | --- |
| `pxxweb/content/compliance/overview.md` | 14 | `<span class="cstat exp">Experimental</span>` — the one the owner named |
| `pxxweb/content/frontpage.md` | 9 | "nilpy (python dialect) **staged**" |
| `pxxweb/content/about.md` | 11 | "dialect, is **staged**" |
| `pxxweb/config.py` | 12 | site-wide meta description: "(nilpy) **in development**" |

`config.py` matters more than its size suggests: that string is the `<meta
name="description">`, the `og:description` and the `twitter:description` on
**every page**, so it is what search engines and link unfurlers quote. Fixing
the compliance table alone leaves the stale claim on the most-syndicated surface
the site has.

## The docs already disagree, which is the strongest evidence here

`docs/targets/nil-python.md:10`, in the pxx repo, published by this same site:

> It is a **mainline frontend**, a peer of Pascal and C rather than a research
> path: it has its own test gate (`test-nilpy`), which must be green — along
> with a byte-identical self-host and the cross-target builds — before any
> change lands. BASIC, Rust and Zig are the experimental frontends; Nil Python
> began there and no longer is.

CLAUDE.md says the same: N is **mainline** (peer of C, *not* experimental like
R/Z), with its own carved-out files and a gated suite. So the site currently
contradicts both its own docs and the project's charter, on a page whose whole
subject is telling people what is true.

## Why "open bug tickets" is not a counter-argument

The owner pre-empted this and he is right. Every mainline frontend carries open
tickets; Pascal and C carry more, and neither is billed as experimental.
**"Experimental" is a statement about commitment and gating, not about defect
count** — R and Z are experimental because they are unranked, optional and
ungated, which is precisely what NilPy is not.

## Scope

Change the four strings. Keep the *class* of claim honest — "mainline",
"gated", "peer of Pascal and C" are all supportable from the gate; do not
upgrade the language further than the docs already go.

## A SECOND claim on the same line, NOT covered by the owner's call

`compliance/overview.md:14` also says:

> Python _syntax_ only — the CPython library ecosystem is out of scope (pxx is a
> compiler, not a Python runtime)

That may be stale too — `feature-nilpy-stdlib-coverage-gaps-measured`,
`feature-nilpy-thirdparty-libraries-as-targets` and the SQLite/tkinter work all
point the other way, and CLAUDE.md's rule is that NilPy is **upward compatible
with CPython** ("if code works on CPython, it must work on NilPy"), which is not
the posture of a project treating the library ecosystem as out of scope.

**Do not change it on this ticket.** The owner spoke to "experimental" only.
Flagged so whoever edits line 14 notices they are standing next to a second
claim, and asks rather than tidies.

## SECOND ITEM, same page, same edit pass — soften "never" on C++

Owner, 2026-08-27:

> *"oh, and same page lists c++ as 'never'. i'd say, that's still accurate.
> just, never say never."*

**The substance is endorsed and does not change.** C++ is not planned, the
reasoning below the table is sound, and nothing here promises a C++ frontend.
Only the absolute goes.

Two places, and they must move together — softening the table row while the
prose underneath still says "deliberately never" reads worse than leaving both:

| file | line | current |
| --- | --- | --- |
| `pxxweb/content/compliance/overview.md` | table row | `<span class="cstat exp">Never</span>` · "Will not be implemented — see below" |
| same file | `## C++ — deliberately never` | "C++ **will not be implemented**. … The cost never justifies the payoff." |

Suggested shape, not prescribed wording: `Not planned` in the status cell, and a
heading and paragraph that give the same reasons in the present tense — the
grammar is huge and context-sensitive, the build model drags in a heavyweight
toolchain, the cost does not justify the payoff **today**. That says everything
the current text says about intent while not committing the project to a
position it would have to eat later.

**Why this is worth doing rather than pedantry:** the page's own opening
sentence promises "the honest map". An absolute is a claim about the future,
which is the one thing a status page cannot measure — and it sits three rows
below a `Never` on a language that has an experimental frontend two rows up.
The credibility cost of an unnecessary absolute is paid the day it changes, and
this project has already had to correct one over-strong claim class (see
CLAUDE.md's byte-identical discipline). Same failure, smaller stakes.

Note the status cell also uses `class="cstat exp"` — the *experimental* colour —
for `Never`, which is a class mismatch rather than a style choice. Fix or leave,
but notice it.

## Lane note

The owner called this "a small track D notice". Filed as **W** because D owns
`docs/**` in the pxx repo and these files are `pxxweb/content/**` in the website
repo — the letter follows file ownership, which is what the lanes are for. The
work itself is D-shaped prose. Noted rather than silently reclassified.

## Log
- 2026-08-27 — resolved, commit f6f9879d9.
