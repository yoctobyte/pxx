---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`max(d)` / `min(d)` over a DICT raise `TypeError: max() argument is not iterable`; CPython answers the largest/smallest KEY. Every other iterable works, and `sorted(d)` over the same dict already does the right thing."
status: done
owner: agent-AN
---

# max()/min() do not iterate a dict

```python
print(max({"k": 1, "z": 2}))     # CPython: z      pxx: TypeError: max() argument is not iterable
```

Found 2026-08-14 while adding `max(xs, default=D)`
([[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]] item 4) — the
`default=` row for a dict raised, and the raise turned out to have nothing to do
with `default=`: plain `max(d)` does it too.

## Why it is worth fixing rather than documenting

Iterating a dict yields its KEYS everywhere else in this frontend — `for k in d`,
`list(d)`, `sorted(d)` and `in` all agree with CPython. `max`/`min` are the
outliers, so this is an inconsistency inside NilPy, not a deliberate divergence.

`sorted` is the precedent to copy: it grew a dict overload
(`sorted(d: TPyDict; key; reverse)`) that delegates to the list form over
`keylist`, so the ordering logic stays in one place. `max`/`min` want the same
one-line delegation.

## Failure mode

A loud TypeError, which is the good case — no silent wrong value.

## Gate

A `.npy` diffed against CPython: `max(d)`, `min(d)`, both with `default=` on an
empty dict and a populated one, and `max(d, key=d.get)` if that resolves.

## Resolution (2026-08-15)

`max(d)` / `min(d)` answer the largest/smallest KEY, as every other iteration of
a dict in this frontend already did.

**Fixed by deleting the special cases, not by adding one.** The ticket suggests
copying `sorted`'s dict overload; the better shape turned out to be one level
up. `max`/`min`'s variant arms each carried their OWN "what is iterable" chain —
`o is TPyRange` -> materialise, `o is TPyIter` -> drain, anything else ->
TypeError — which is a second answer to a question `pylist_v` already answers
for `list()`, `sorted()`, `in` and the rest. Both arms now call `pylist_v` and
walk the result.

That fixed four rows at once rather than the one the ticket reports: **dict,
bytes, and a USER class with `__iter__`** all became iterable to `max`/`min` for
free, and cannot drift from the other consumers again.

**A second site had the same bug in a different disguise.** `PyMinMaxByKey`
(the `key=` path) indexed the container with `pyvar_getitem(c, 0)` — which for a
dict is a KEY LOOKUP, so `max(d, key=len)` raised `KeyError: 0`. Found by
testing the `key=` row rather than assuming the plain one covered it; it now
goes through the same `pylist_v`. Two mechanisms serving one concept is the
smell `normalise-dont-special-case` names, and this was it.

**Diagnostic parity, found by the diff:** CPython says `max() iterable argument
is empty`; we said `max() arg is an empty sequence` (CPython's OLDER wording) in
six places, including a `min()` message on the `max(xs, key=f)` path — a small
lie in a diagnostic. All six corrected, and the key= arm now names the builtin
the caller actually wrote.

**Gate:** `test/test_nilpy_max_min_iterables.npy` (+`.expected`, wired into the
Makefile) — dict (bare, `.keys()`, `.values()`, `default=`, `key=`), plus list,
str, range, bytes, a generator, a tuple and `key=` over lists, the two-argument
numeric form that must stay itself, and the empty-sequence ValueError.
Byte-identical to CPython. The four existing `test_nilpy_min_max_*` tests
re-diffed unchanged. `tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
