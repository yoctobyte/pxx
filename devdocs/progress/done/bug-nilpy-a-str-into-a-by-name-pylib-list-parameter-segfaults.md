---
track: N
prio: 50
type: bug
blocked-by: []
summary: "`random.choice(\"abc\")`, `math.fsum(\"ab\")` and `math.prod(\"ab\")` all SEGFAULT — a str reaches a pylib TPyList parameter through a by-name lowering that cannot resolve overloads by type. Swept as a population rather than reported one at a time; `random.shuffle` is the deliberate exception because pylist_v copies."
---

# A str into a by-name pylib list parameter segfaults

Found 2026-08-16, sweeping the population named in
[[project_nilpy_byname_findproc_lowerings_are_the_unchecked_population]]
immediately after [[bug-nilpy-dict-fromkeys-of-a-str-segfaults]] — the note says
to grep the by-name lowerings against pylib's `TPyList`-taking routines and
enumerate the crashes, and that is what this is.

## Measured

```python
random.choice("abc")   # CPython 'a'                   pxx SIGSEGV
math.fsum("ab")        # CPython TypeError             pxx SIGSEGV
math.prod("ab")        # CPython TypeError             pxx SIGSEGV
random.shuffle("abc")  # CPython TypeError             pxx silent no-op
```

`random.choice` over a str is the sharp one: it is a **working CPython
program**, not an error case, and picking a random character from a string is
what the function is for.

## Cause

`PyParseStdlibCall` builds these calls **by name** and re-targets only by
ARITY. A `TPyList` parameter therefore accepted a str and dereferenced it as an
object.

## Fix — in the callee, and not uniformly

`pymath_prod`, `pymath_fsum` and `pyrandom_choice` take a **Variant** and go
through `pylist_v`, the one bridge that turns any Python iterable into a list
and raises a named TypeError for anything else. A call-site check would have to
be repeated per site, which is the whole point of the population note.

**`random.shuffle` is deliberately NOT that**, and it is why this needed a
sweep rather than a sed: `pylist_v` COPIES, so shuffling its result would
shuffle nothing the caller can see — a silent no-op, strictly worse than the
crash. It takes the real `TPyList` out of the variant and refuses everything
else by name, which is also CPython's answer (`TypeError: 'str' object does not
support item assignment`).

## Gate

`test/test_nilpy_by_name_list_params_take_a_str.npy` — str, list and tuple
receivers for `choice`, in-place `shuffle` plus its str refusal, and `fsum` /
`prod` over both a list and a tuple. Output identical to CPython's on every
row; the random VALUES are not asserted (the generator is not CPython's), so
the rows assert membership and length instead. `gate.sh quick` green.
