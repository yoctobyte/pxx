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

## DECIDED 2026-08-08 (user): STAY LAX — a documented divergence, not a bug

> not fixing it wouldn't harm anything and we can still take code as cpython
> does? ... as long we are forward compatible we are good. i'm not worried about
> code that works under pxx and not under cpython. not our issue. and pxx is our
> party. as long we compile what cpython can. again - only if there is
> ambiguity, there may be a reason for strict

NilPy keeps accepting the positional spelling. This is the NilPy rule working as
designed: **forward compatibility only** — everything CPython accepts must work
here; accepting more is a language feature.

Two corrections to the framing this ticket was filed under:

- **The harm was overstated.** A pxx-only spelling fails LOUDLY on CPython with a
  `TypeError`. The cost is deferred discovery of a portability issue, not a wrong
  answer — a different class from the silent-wrong-value bugs that justify
  strictness here.
- **The Pascal/C-caller argument does not discriminate.** The enforcement would
  have gone at the NilPy CALL SITE (the only place that still knows which
  arguments were written positionally), so a Pascal or C caller reaching
  `sorted()` through its ordinary defaulted-positional signature would never have
  seen it either way.

### The ambiguity clause was CHECKED, not assumed

The user's qualifier — *"only if there is ambiguity, there may be a reason for
strict"* — is the real risk for `min`/`max`, whose signature is
`min(arg, *args, key=None)`: the second POSITIONAL slot means another VALUE, not
`key`. If pxx bound it to `key`, `min(a, b)` on two comparable values would
silently mean something else, and that WOULD break forward compatibility.

Measured at HEAD — it does not:

| | pxx | CPython |
| --- | --- | --- |
| `min(3, 5)` / `min(3, 5, 1)` | `3` / `1` | same |
| `min([1,2], [1,3])`, `max(...)` | `[1, 2]` / `[1, 3]` | same |
| `min("apple", "banana")` | `apple` | same |
| `min(words, key=len)` | `a` | same |
| `min(words, len)` | `a` | **TypeError** |

pxx disambiguates on **callability**: a callable second argument is `key`,
anything else is another value. Every realistic valid CPython program takes the
value reading and agrees. The single divergent row is a spelling CPython refuses
outright.

The heuristic's limit, for the record: an object that is BOTH callable and
orderable, passed as the second value, would take the `key` reading here and the
value reading in CPython. No such program is worth designing against.

### Future path, if portability checking is ever wanted

A `--strict-python`-style per-feature flag, matching `--strict-case` /
`--strict-overload`. **Default stays lax** — the flag is the shape any future
request takes, so nobody re-litigates the default in order to get the check.

Logged in `devdocs/dev/nilpy-semantics-divergences.md`, which is where
"laxer than CPython" belongs rather than in a bug ticket.

Does NOT block [[bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error]]:
that ticket needs `key=`/`reverse=` to WORK, which is orthogonal to whether the
positional spelling is also accepted.
