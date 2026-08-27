---
track: W
prio: 55
type: docs
blocked-by: []
summary: "The website bills NilPy as experimental in four places — the compliance table says `Experimental`, the frontpage and about say `staged`, and the site-wide meta description says `in development` — while `docs/targets/nil-python.md` in the pxx repo already says the opposite (mainline frontend, peer of Pascal and C, gated by test-nilpy). Owner's call 2026-08-27: Python is a first-class citizen now, open bug tickets notwithstanding. Content files live in the website repo, so this is W by file ownership even though the work is D-shaped."
status: backlog
---

# The website still bills NilPy as experimental; the docs already say otherwise

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

## Lane note

The owner called this "a small track D notice". Filed as **W** because D owns
`docs/**` in the pxx repo and these files are `pxxweb/content/**` in the website
repo — the letter follows file ownership, which is what the lanes are for. The
work itself is D-shaped prose. Noted rather than silently reclassified.
