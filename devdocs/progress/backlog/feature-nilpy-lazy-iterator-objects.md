---
track: N
prio: 55
type: feature
blocked-by: []
summary: "UMBRELLA: map/filter/enumerate/zip/reversed return eager LISTS where CPython returns cursor objects, so a working CPython program can crash here (f runs for every element even when the loop breaks early, and a raise past the break point escapes). Build a real cursor — TPyIter in pylib, consumed by every for/list/sum/sorted site — and give iter()/next() somewhere to live"
---

# UMBRELLA: real lazy iterator objects for map / filter / enumerate / zip / reversed

- **Type:** feature (NilPy) — **Track N**
- **Decided:** [[decide-nilpy-eager-map-filter-reversed-enumerate]] (user,
  2026-08-12) — build the real thing. **Read that ticket first**: it holds every
  measurement behind this one, and the model in one table.
- **Opened:** 2026-08-12, from the differential builtin sweep.

## Why, in one measurement

`f` counts its calls; `xs = list(range(10))`:

| | after `m = map(f, xs)` | after breaking at 3 | second pass over `m` |
| --- | --- | --- | --- |
| CPython | **0 calls** | 3 | yields the remaining **7** |
| pxx | **10 calls** | 10 | yields all **10** again |

CPython's `map` is a **cursor** — an enumerator, or a database cursor — and
`for n in m` calls Next. Constructing one costs nothing; breaking parks it;
resuming continues from there. Nothing is detected or optimised: `map` is a
CLASS, `map(f, xs)` is a constructor call, and laziness is the object's
contract. pxx returns a list — i.e. **Python 2's `map`**.

The consequence that makes this a correctness ticket rather than a perf note:

```python
def risky(x):
    if x > 5:
        raise ValueError("too far: " + str(x))
    return x

out = []
for v in map(risky, list(range(100))):
    out.append(v)
    if len(out) == 3:
        break
```

CPython prints `survived [0, 1, 2]`; pxx raises `ValueError: too far: 6`. A
program CPython accepts and runs crashes here, which is the one thing the
upward-compatibility rule does not bend on.

## What "done" looks like

Every row below matching CPython, in a `.npy` diffed against it:

1. `m = map(f, xs)` performs **zero** calls of `f`.
2. `for v in map(f, xs)` with an early `break` calls `f` exactly as many times
   as elements consumed — and a raise past the break point never happens.
3. A second pass over the same bound cursor yields the **remainder**, not the
   whole thing and not nothing.
4. `list()`, `sorted()`, `sum()`, `in`, a `for` header and a comprehension all
   consume one correctly.
5. `print(m)` shows `<map object at 0x…>`; `type(m).__name__` is `map`
   (`filter`, `enumerate`, `zip`, `list_reverseiterator`).
6. `iter(xs)` and `next(it)` exist and work, including `next(it, default)` and
   the `StopIteration` on exhaustion.

## The pieces, in landing order

Each step is independently green — do NOT hold a long-lived broken state.

1. **`TPyIter` in pylib** — source (a TPyList, a str/bytes, a dict, or another
   cursor), a position, a kind, an optional stored callable, and a `next`
   returning a variant plus an exhausted signal. Plus the `iter()` / `next()`
   builtins, which have nowhere to live today
   ([[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]]). Testable
   on its own, before any existing builtin changes behaviour.
2. **Teach the consumption sites to accept one** — the `for` container path
   (`PyParseForIn`), `list()`, `sorted()`, `sum()`, `in`, and comprehensions.
   Still no behaviour change: nothing produces a cursor yet.
3. **Switch `map`**, then `filter`, `enumerate`, `zip`. One per commit, each
   with its own gate — a regression here is much easier to place per-builtin.
4. **`reversed` last.** Its source is already a materialised sequence, so the
   only observable gain is the exhaustion rule; it is the cheapest to defer if
   the budget runs out.

`range` is deliberately OUT of scope. It cheats differently — it is not a value
at all (`r = range(3)` is `undefined variable (range)`) and CPython's is a lazy
SEQUENCE (re-iterable, indexable, `len`-able), not a cursor. Its own ticket.

## The one BEHAVIOUR REMOVAL — check the suite before you start

`len(map(...))` answers **2** in pxx today and raises
`TypeError: object of type 'map' has no len()` in CPython. Going lazy makes that
row stricter, and stricter is the direction the upward-compatibility rule
normally forbids — but it is allowed here precisely because CPython REJECTS the
code, so no working CPython program can depend on it (the rule is one-way).

Still: grep `test/*.npy`, `examples/**` and `lib/**` for `len(` over a
`map`/`filter`/`zip`/`enumerate` result before switching each builtin. If
something in the tree relies on it, decide deliberately — raise like CPython
(recommended) or keep answering by materialising (laxer, but it costs the whole
point of the change for that call).

## Landmines this work walks straight into

- **A stored callable is the hazard.** `map` must keep `f` inside the cursor,
  and a callable has THREE representations here — crossing them writes a
  variant TAG into a pointer slot and faults far away
  ([[project_nilpy_callable_has_three_representations]]). A `map(lambda …)`
  payload is an interpreted pyeval source closure, which is a fourth shape
  again ([[project_nilpy_every_lambda_is_an_interpreted_source_closure]]).
  Test `map` with: a `def`, a lambda, a bound method, and a builtin (`str`).
- **pylib is `compiler/builtin`**, so every step needs `stabilize-fast` + `pin`
  after its gate, not just a commit.
- **The nilpy suite is the family sweep** for anything touching variant
  lowering ([[feedback_variant_lowering_change_needs_the_nilpy_suite]]) — quick
  alone will not see it.
- **Two passes must agree** on any return type this touches: the shell pre-pass
  and the body pass disagreeing is a silent ABI mismatch, and this session hit
  that fault line three separate times.

## Gate

Per step: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` +
`make test-nilpy` + `stabilize-fast`/`pin`. The final step additionally runs
the six "done" rows above as one `.npy` diffed against CPython, and re-runs the
early-break/raise program from the decide ticket, which is the acceptance test
for the whole umbrella.
