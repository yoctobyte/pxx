---
prio: 40
type: decide
track: U
---

# Should NilPy builtins enforce Python's KEYWORD-ONLY parameters?

Filed 2026-08-04 from Track A+N overnight work, while sizing
[[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]]. Parked
rather than guessed at, because either answer is defensible and the choice binds
a growing set of builtins.

## The fork

Several Python builtins declare parameters that are **keyword-only** — CPython's
signature puts a bare `*` before them, so they can be passed by name and only by
name:

```python
list.sort(*, key=None, reverse=False)
sorted(iterable, /, *, key=None, reverse=False)
min(arg, *args, key=None, default=...)
max(arg, *args, key=None, default=...)
```

```python
xs.sort(len)           # CPython: TypeError: sort() takes no positional arguments
sorted(xs, len)        # CPython: TypeError: sorted expected 1 argument, got 2
```

We implement these as ordinary Pascal routines with defaulted parameters:

```pascal
function sorted(l: TPyList; key: Pointer = nil; reverse: Boolean = False): TPyList;
```

A Pascal parameter list has no notion of keyword-only, so **we accept the
positional spelling that CPython rejects**. This is live today for `sorted`,
`min` and `max` (the `min(words, len)` form is recorded as working in that
ticket's 2026-08-04 note, where it was used as the measurement that isolated the
keyword-promoter blocker), and it will be live for `list.sort` the moment
`reverse=` lands.

## Why it is not obviously a bug worth fixing

It is a **laxness**, not a wrong answer: `min(xs, len)` computes what the reader
plainly means, and no correct Python program can tell the difference, because no
correct Python program contains that spelling. It costs nothing at run time and
breaks nothing that exists.

It is also exactly the shape CLAUDE.md says the dialect defaults to — "PXX's own
dialect stays deliberately lax by default; FPC-parity strictness lives behind
per-feature strict flags".

## Why it might still matter

- **It is a silent divergence in the direction we usually refuse.** Code written
  against pxx that uses the positional form will not run on CPython, so the
  laxness quietly produces non-portable Python. That is the mirror image of the
  usual concern, and arguably worse: the artifact is a `.py`-shaped file that
  only our compiler accepts.
- It grows. Every builtin gaining a `key=`/`default=` parameter inherits it, and
  the set is expanding right now (`sort`, `sorted`, `min`, `max`, and the
  `heapq`/`itertools` surface behind them).

## Options

1. **Leave it lax (status quo).** Zero work. Accept that pxx admits a spelling
   CPython rejects, and note it in the dialect docs.
2. **Diagnose it under an existing strict flag.** Needs a per-parameter
   "keyword-only" mark the Pascal signature cannot currently carry — so either a
   parallel array beside `ProcParam*` (the established pattern here; a new field
   on the proc record is the known landmine) or a naming convention the frontend
   reads. Then refuse the positional spelling only when the flag is on.
3. **Always refuse the positional spelling for these builtins.** Full parity, no
   flag. Costs the same machinery as (2) minus the flag, and would break any pxx
   code already written against the lax form.

**Recommendation: (1) for now, revisit if the strict-mode sweep touches
builtins.** The machinery in (2)/(3) is real work for a divergence nobody has
hit, and `compat` tagging exists precisely so parity items can idle at low
priority until someone wants them. Recorded so the next person to add a `key=`
parameter does not have to re-derive the question.

Related: [[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]],
[[bug-nilpy-keyword-arg-vs-overload-set]], [[meta-dialect-extensions-and-fpc-strict]].
