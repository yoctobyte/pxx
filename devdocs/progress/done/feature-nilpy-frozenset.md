---
track: N
prio: 45
type: feature
blocked-by: []
summary: "`frozenset(...)` is undefined — html5lib/constants.py's next wall after the adjacent-string-literal fix (line 305). A set is already a TPyList marked PYSEQ_SET, so the value side is nearly free; the question the ticket has to answer is repr and type name, where frozenset is VISIBLY different from set."
status: done
owner: claude-A-N
---

# `frozenset(...)`

- **Type:** feature (builtin) — **Track N**
- **Found:** 2026-08-13. With the adjacent-string-literal bug fixed,
  `html5lib/constants.py` compiles from line 20 to **line 305**, where it stops
  at `undefined variable (frozenset)` — see
  [[feature-nilpy-thirdparty-libraries-as-targets]].

## What is nearly free

A NilPy set is a `TPyList` stamped `PYSEQ_SET` (`PyMarkAsSet`), and every set
form — `set(...)`, a `{a, b}` literal, a set comprehension — goes through that
one stamp. `frozenset(xs)` produces the same value, so recognising the name
beside `set` in `PyIsSetCall` and friends is the bulk of it.

**Immutability is NOT the hard part.** A NilPy frozenset that can be mutated is
the dialect being laxer than CPython, which is a feature and not a defect by
Track N's own upward-compatibility rule (`devdocs/dev/nilpy-semantics-divergences.md`):
no program that CPython accepts and runs can observe it, because CPython would
have raised.

## What the ticket must actually decide

`frozenset` is **visible** in two places, and getting these wrong IS a defect
because ordinary working code observes them:

- `repr` — CPython prints `frozenset({1, 2})`, a set prints `{1, 2}`. A program
  that prints one would silently print the other.
- `type(x).__name__` and `isinstance(x, frozenset)` — both answer `set` today if
  the stamp is shared.

So it wants a THIRD sequence kind (`PYSEQ_FROZENSET`) beside list/tuple/set
rather than reusing the set stamp, which is the same call
[[bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance]] already
made once for set-vs-list. That is a pylib `FKind` value plus its arms in the
renderer, `isinstance`, and `type().__name__` — the three-rendering-paths and
subscript-protocol matrices in this repo's NilPy notes are the checklist.

## Gate

A `.npy` diffed against CPython: construction from a list/tuple/generator,
`in`, `len`, iteration, equality with a set, `repr`, `type(x).__name__`,
`isinstance(x, frozenset)` and `isinstance(x, set)` (CPython: a frozenset is
NOT a set instance), plus `html5lib/constants.py` getting past line 305.

## DONE 2026-08-13

`frozenset(...)` constructs, prints, compares and answers `isinstance` — every
row of this ticket's gate matching CPython: construction from a list, a tuple, a
string and a generator expression, `in`, `len`, iteration, equality with a set,
`repr`, `type(x).__name__`, `isinstance(x, frozenset)`, `isinstance(x, set)`
(False, as CPython has it) and the empty `frozenset()`.

Built exactly as the ticket said to: a THIRD sequence kind, `PYSEQ_FROZENSET`,
rather than reusing the set stamp. The value side is the shared path — one
parse, one `pyset_of`, then a different stamp on the way out — and the three
places the kind is VISIBLE each grew an arm:

- **repr**: `frozenset({1, 2})` and the empty `frozenset()`. Written as a
  prefix/suffix around the SET display rather than a third bracket pair,
  because that is what it is.
- **`type().__name__`**: `PySeqKindName` answers `frozenset`.
- **isinstance**: `frozenset` is `KindEq(PYSEQ_FROZENSET)`, so a frozenset is
  not a set and a set is not a frozenset — both directions checked.

**Equality is the row where kind identity is WRONG**, and it was the one worth
thinking about: CPython's `frozenset({1, 2}) == {1, 2}` is True — frozenset is a
different TYPE, not a different value — while both stay unequal to a list. So
`pylist_eq`'s guard (added hours earlier for set-vs-sequence) tests
set-LIKENESS, not kind equality.

Immutability is not enforced, per the ticket's own reasoning: a mutable
frozenset is the dialect being laxer than CPython, which no program CPython
accepts and runs can observe.

`PyMarkAsSet` was generalised to `PyMarkAsSeqKind(node, marker)` with the two
stamps as thin wrappers — one builder, so a fourth kind is a line rather than a
copy.

Test `test/test_nilpy_frozenset.{npy,expected}` (`.expected` from CPython),
wired into `test-nilpy`; the four existing set tests re-run unchanged. Gate:
self-host fixedpoint + `gate.sh quick` GREEN.

**Not verified here:** whether `html5lib/constants.py` now gets past line 305 —
that belongs to [[feature-nilpy-thirdparty-libraries-as-targets]], which owns
the corpus run.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
