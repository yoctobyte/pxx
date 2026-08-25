---
track: B
prio: 65
type: feature
blocked-by: []
summary: "The ladder's three corpora are ONE FAMILY, not three samples — same domain, overlapping lineage, and tinycss2 literally imports webencodings. Two days of NilPy ranking rest on it. Measure an idiom-distant fourth corpus and report against the prediction: either the walls generalise, or some of what we rank at 70 is a webencodings-shaped preference."
---

# A fourth corpus — do the ladder's walls generalise, or are they one family's idioms?

Filed 2026-08-19 by frank3-etree (Track B), from the coordinator's sharpening of
a weaker version of this argument. Track B work: fetching and wiring only, **no
compiler change**.

## The problem with the current sample

`tools/nilpy_ladder.py` tracks `webencodings`, `html5lib`, `tinycss2`. These are
not three independent data points — they are **one family**:

- one domain (web parsing / text encoding),
- overlapping authorship and lineage,
- and a hard dependency edge: **`tinycss2` imports `webencodings` directly**
  (`tinycss2/bytes.py:1`, `ast.py:8`, `tokenizer.py:4` — verified, not assumed).

So the corpus is closer to *one codebase in three pieces* than to three samples,
and the entire NilPy priority ranking of the last two days is derived from it.
Every wall we have chased — `decode(final=)`, `unknown base class Mapping`,
`*unpacking into TreeWalker.doctype` — comes from that family.

## What a good fourth corpus stresses

Deliberately what a web parser barely touches: heavy numeric/algorithmic code,
generators and iterator protocols used in anger, descriptors and properties,
context managers, `__slots__`, exception-heavy control flow, deep recursion,
operator overloading on user classes. Constraint: **pure Python, no C
extensions, few dependencies.**

## Start with reportlab — it is already on disk and costs nothing

`library_candidates/reportlab` is **already fetched** (as the oracle for
`lib-test`'s reportlab-diff), is **421 `.py` files with zero `.c`**, and is
about as far from a web parser as this repo currently holds: PDF generation,
graphics primitives, deep class hierarchies, numeric layout code.

`nilpy_ladder.py`'s `corpora()` deliberately excludes it — only the flat
`<name>/<name>/__init__.py` layout counts, and reportlab is `src/reportlab/…`.
That exclusion is correct **and must stay**.

> **Do NOT add it as a rung.** The ladder's `compile: N/48` is a time series —
> 6/48, 10/48, 10/48 across four pins — and changing the denominator destroys
> comparability with every reading taken so far. Measure it as a **separate
> probe** with its own baseline.

If reportlab's walls turn out to duplicate the family's, fetch something with a
different shape again (`attrs`, `jsonschema`, `pyparsing`, `chardet` are the
right size and are pure Python).

## The deliverable is a verdict, not a table

Report **against the prediction**, explicitly:

- **The walls generalise** — a distant corpus stops on the same things. The
  ranking stands and is now evidence-based rather than assumed.
- **They do not** — the new corpus stops on walls never seen. Then the campaign
  re-bases, and some of what is ranked at 70 is a *webencodings-shaped
  preference* rather than a general gap.

The second outcome is the more valuable and the easier to miss, because a table
of counts does not say it. Say it in words.

## Gate

Track B: build with `$(PXX_STABLE)`, never rebuild the compiler. No `make
lib-test` impact expected (nothing wired into the gate). Name the pin md5 and
base — `nilpy_ladder.py` now prints both in its header — and use
`--require-fix=<sha>` when the run is meant to measure a specific fix.


## 2026-08-19 — PARKED (goal change), with the thesis partly CONFIRMED before it was

Parked at a clean point when the user changed the goal to backlog-shrink and
NilPy was paused. Nothing was in flight; the v360 ladder run was stopped
deliberately rather than left to finish, because a measurement whose consumer is
paused is the definition of work that does not matter — and it was competing for
CPU with work that does.

**The thesis is already confirmed on at least one rung**, which is why this is
worth resuming rather than re-deriving. frank2 established that `re.MULTILINE`
— a wall reached by tinycss2 the moment the callable-value fixes landed — is a
**Track B library-surface gap and not a mechanism bug**: `lib/rtl/re.pas` says in
its own header that it *is* NilPy's `re`, and simply does not define
`MULTILINE`.

That is exactly the distinction this ticket was filed to test. Two days of walls
were all one mechanism (callables, signatures, dispatch); the first wall past
them is a missing constant in a library. If the remaining distance is largely
library-surface rather than semantics, then **what gets ranked next depends
heavily on which libraries we happen to have fetched** — and a corpus of three
packages from one family is choosing those priorities for us.

Related, same shape, also from frank2 and also parked: eight `lib/rtl` units
share a name with a Python stdlib module (`classes io json math random re
strings types`), so `from classes import Foo` fails naming a symbol in a Pascal
unit the program never mentions. Filed as a Track U decision rather than guessed
at.

**Resume condition:** NilPy unpaused. Start with reportlab as a separate probe
(already fetched, 421 pure-Python files, zero C), and do not touch the ladder's
tracked roots — the `compile: N/48` series must stay comparable.
