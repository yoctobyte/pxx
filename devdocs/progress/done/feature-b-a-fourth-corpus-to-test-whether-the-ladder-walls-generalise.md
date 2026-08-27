---
track: B
prio: 65
type: feature
blocked-by: []
summary: "The ladder's three corpora are ONE FAMILY, not three samples — same domain, overlapping lineage, and tinycss2 literally imports webencodings. Two days of NilPy ranking rest on it. Measure an idiom-distant fourth corpus and report against the prediction: either the walls generalise, or some of what we rank at 70 is a webencodings-shaped preference."
status: done
owner: frankB
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

## 2026-08-28 (frankB, Track B) — RESOLVED. **The walls do NOT generalise**, and the reason is sharper than "different walls".

Measured `library_candidates/reportlab` 4.2.5 (421 `.py`, 0 `.c`) as a **separate
probe** at pin v389 — `md5 0453ed506a14e464fd6c6cf0d81c6a55`, base
`83468c5462d40294a7e7a5885a61fbac20077285`. Added `--probe=<dir>` to
`tools/nilpy_ladder.py`: it reuses the exact scan method but keeps its own
baseline and puts only its own roots on `-Fu`, so `corpora()` and the
`compile: N/48` series are untouched, as this ticket required.

```
compile: 36/159      (probe baseline — not a rung, not comparable to N/48)
123 failures, 30 distinct first walls
```

### The answer, in words

**Not one of reportlab's 30 distinct walls is a wall the family produced.** The
family's walls — and therefore everything this campaign ranks between 55 and 70:
`staticmethod-and-classmethod` [70], `user-defined-decorators` [68],
`iter-and-next-over-a-container` [65], `list-sort-inplace-key-reverse` [62],
`enum-class` [62], and the whole `bug-n-*-callable-value` / `*-keyword-argument-*`
/ `*-untyped-receiver-*` cluster at 55 — are **mechanism and dispatch** items.
reportlab hits none of them.

But the interesting part is *why*, and it is not "a distant corpus stops on
different mechanisms". **89% of reportlab's failures (109 of 123) are library
surface** — a missing stdlib module, or a missing member of one. 6% are syntax
(triple-quoted f-strings, one tabs/spaces file, two f-string conversion gaps);
7 files I did not classify and am not counting either way.

reportlab never *reaches* the mechanism layer. It stops at its first missing
import. Of the 17 stdlib modules its top walls name, **16 have no shim at all**:

```
functools pickle importlib binascii encodings hashlib unicodedata datetime
inspect logging marshal operator pprint struct tokenize weakref     — ABSENT
re                                                                  — lib/rtl/re.pas
```

So the family's mechanism walls are not *wrong*. They are **conditional**: they
are what a corpus hits *once its import surface is already covered*.
webencodings / html5lib / tinycss2 have almost no stdlib footprint — that is
what a self-contained web parser *is* — so they arrived at the mechanism layer
immediately and have been generating the ranking ever since.

**That is the webencodings-shaped preference, and it has a specific shape: the
ranking is shaped by unusually low-dependency code.** It ranks mechanism above
library surface because the sample had essentially no library surface to rank.

### The prediction this licenses, and it is testable

On a corpus with an ordinary stdlib footprint, landing the 55–70 mechanism
cluster would move the compile count by **approximately zero**, because those
items sit behind sixteen missing modules. This is precisely the trap
`bug-a-package-and-sibling-module-resolution-is-the-corpus-wall` already
recorded one level down — `six` gated 15 files and landing `mimic_six` moved
4/48 to 4/48 — except at corpus scale rather than file scale. Same rule applies
and is worth restating: **compile count lags, walls-cleared leads.**

### The #1 wall is a boundary case worth naming

`undefined variable (os)`, 30 files, is nominally library surface but is really
the seam between two implementations of one concept. `os.getcwd()`,
`os.path.join()`, `os.getenv()`, `os.environ.get()` all compile — they are
dotted calls special-cased in `compiler/pyparser.inc`. `'HOME' in os.environ`
and `os.sep` fail, because there is no `os` *module value* behind the
special-case (`pyparser.inc:11852` accepts only `seek_set/cur/end`). One leaf
file — `reportlab/lib/__init__.py`, seven lines, last line
`RL_DEBUG = 'RL_DEBUG' in os.environ` — gates all 30. Filed as
`bug-n-os-environ-and-os-sep-are-not-values` [N, p60]. It is a textbook
`devdocs/dev/normalise-dont-special-case.md` case: the second path is the one
that stayed broken.

### What should change

Not the mechanism tickets — they are real and will be needed. What is missing is
that **the campaign has no measurement of library surface at all**, and the one
ticket that would produce it,
`feature-nilpy-stdlib-coverage-gaps-measured` [72], is the highest-ranked NilPy
feature in the backlog and has never been started, while the mechanism items
below it get worked. This probe is an argument for starting it: it is now the
leading indicator, and the ranking beneath it was derived from a sample that
could not see it.

### Limitation, stated so it is not over-read

I did **not** re-run the family at v389 for a same-pin like-for-like; the run was
killed at ~15 minutes with box load at 9.5 while Track T held a full tier, and it
was redundant — the comparison here is *categorical* (mechanism vs library
surface), not numeric, so it does not turn on the family's exact counts today.
The family's walls are taken from the campaign record, which is the right source
anyway: those are the walls the ranking was actually derived from.

Per this ticket's own instruction, if reportlab had duplicated the family's walls
the next step was another corpus. It did not, so it needs no follow-up corpus —
it needs the stdlib-coverage measurement.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
