---
track: N
prio: 30
type: bug
summary: "NilPy: `del x` on a plain variable is accepted and does nothing — the name stays bound, so reading it afterwards returns the old value where CPython raises NameError. `del lst[i]` and `del d[k]` are correct."
---

# `del x` on a plain variable is a silent no-op

- **Type:** bug (silent semantic divergence) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`.
- Low priority: `del` on a bare name is uncommon, and the container forms —
  which are the ones real code uses — are correct.

## Measured (self-hosted at `54fbd2754`)

```python
x = 5
del x
print(x)            # CPython NameError    pxx 5

s = "hi"
del s
print(s)            # CPython NameError    pxx hi

lst = [1, 2]
del lst
print(lst)          # CPython NameError    pxx [1, 2]

def f():
    y = 7
    del y
    return y        # CPython UnboundLocalError    pxx 7
print(f())
```

Module scope and def scope behave the same. No diagnostic in any case — the
statement parses, compiles, and has no effect.

The container forms are correct and must stay so:

```python
lst = [1, 2, 3]; del lst[1]; print(lst)      # [1, 3]      agrees
d = {"a": 1, "b": 2}; del d["a"]; print(d)   # {'b': 2}    agrees
```

## Why it is worth fixing even at low priority

Silence is the problem, not the missing unbind. `del` on a name is written for
one of two reasons: to drop a reference so an object can be collected, or to
make a later accidental use fail loudly. NilPy grants neither, and the second
one inverts: code that used `del` as a guard rail gets the OPPOSITE of what it
asked for, with no sign.

## Two ways to land it

1. **Actually unbind.** Correct, and it wants a notion of "bound" the frontend
   does not have today (a NilPy local is a frame slot, always present), so it
   likely means a sentinel plus a check on read — a real cost on every read of
   any name that is ever `del`'d.
2. **Refuse it.** `del <name>` becomes a diagnostic ("del of a plain name is not
   supported; del of a list element or dict key is"). Honest, cheap, and turns
   a silent wrong answer into a compile error the author can act on.

Recommend **2** unless someone has a corpus that needs 1 — this repo's own rule
is that a clear refusal beats a plausible wrong answer, and option 1's cost
lands on every read, not just on the `del`.
Escalate to Track U if that reads as a language-surface call rather than an
implementation one.

## Gate

Per-fix loop. A `.npy` test with `del` on a module-scope name, a def-local, and
both container forms (which must stay correct), diffed against CPython — or, if
option 2 is taken, a `{%FAIL}`-style expectation that the bare-name form is
rejected.
