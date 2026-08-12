---
track: U
prio: 55
type: decide
blocked-by: []
summary: "map/filter/reversed/enumerate return LISTS, not lazy iterators. MEASURED: `for v in map(risky, xs)` with an early break raises an exception CPython never reaches (f runs 1000x vs 4x), so a working CPython program crashes — this is an upward-compatibility break, not a perf note. Decide: fuse at the for-loop consumption site (recommended), full iterator protocol, or document"
---

# Decide: eager `map` / `filter` / `reversed` / `enumerate`

- **Track U** (decision) — raised 2026-08-12 from the builtin sweep in
  [[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]].

## The fact

```python
print(map(str, [1]))        # pxx: ['1']   CPython: <map object at 0x7e49b4d06080>
print(filter(None, [0, 1])) # pxx: [1]     CPython: <filter object at 0x...>
print(reversed([1, 2]))     # pxx: [2, 1]  CPython: <list_reverseiterator object ...>
print(enumerate([1], 1))    # pxx: [(1,1)] CPython: <enumerate object at 0x...>
```

NilPy evaluates them eagerly and hands back a list. Every ordinary use agrees
with CPython — `list(map(...))`, iterating one in a `for`, comprehending over
it, `len(list(...))`, `sorted(...)` — because those all consume the whole thing
anyway.

## Why it is a real fork and not just a printing nit

Three shapes of working CPython code CAN observe the difference:

1. **Printing or repring one directly** (above) — harmless but visible, and the
   kind of thing a doctest or a logged debug line catches.
2. **The function runs for EVERY element, even when the loop stops early** —
   and this one can turn a working CPython program into a crashing one.
   Measured:

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
   print("survived", out)
   ```

   | | result |
   | --- | --- |
   | CPython | `survived [0, 1, 2]` |
   | pxx | **`Unhandled exception: ValueError: too far: 6`** |

   The same shape without the raise just wastes work: with an early `break`,
   a counting `f` is called **1000 times under pxx and 4 times under CPython**.
   Any side effect in `f` — a print, a write, a counter, a network call —
   happens N times instead of k.

   Memory is the *lesser* half of this, and much smaller than "explode":
   materialising costs one extra list per stage. Measured over 2,000,000
   elements, peak RSS was 210 MB (pxx) against 88 MB (CPython) — a constant
   factor, not unbounded growth. The genuinely unbounded case needs a lazy or
   infinite source, which needs generators (`yield` is unsupported today —
   [[feature-nilpy-yield-outside-a-for-loop]]), and `map(f, range(n))` does not
   even compile, since `range` is not a value outside a loop header. So today
   the hazard is **wasted work and premature side effects**, not memory.
3. **Single consumption**: a CPython iterator is exhausted after one pass. All
   four, measured:

   ```python
   it = map(str, [1, 2]);  print(list(it)); print(list(it))
   ```

   | | first pass | second pass |
   | --- | --- | --- |
   | CPython | `['1', '2']` | `[]` |
   | pxx | `['1', '2']` | `['1', '2']` |

   and identically for `enumerate`, `reversed` and `filter`. NilPy is *more*
   forgiving here, which by the upward-compatibility rule is a feature, not a
   defect — code that CPython accepts and runs cannot tell the difference,
   because in CPython that second pass is empty and any program relying on it
   would already be broken.

Point 2 is the one that makes working code FAIL rather than differ — measured
above, not reasoned. Points 1 and 3 are cosmetic and laxer-than-CPython
respectively; point 2 alone is what this decision is really about.

## The model, in one measurement — it is a CURSOR, not an array

The clearest way to see what `map` actually IS. `f` counts its calls:

```python
m = map(f, xs)                 # xs = list(range(10))
print("after binding m:", calls)
for n in m:                    # break after 3
    ...
print("after breaking at 3:", calls)
for n in m:                    # a SECOND pass over the same m
    ...
```

| | after binding | after breaking at 3 | second pass yields |
| --- | --- | --- | --- |
| CPython | **0 calls** | 3 calls | **7** more (elements 4-10) |
| pxx | **10 calls** | 10 | **10** again |

CPython's `map` is an **enumerator/cursor** — `IEnumerator`, or a database
cursor — and `for n in m` calls Next. Constructing one costs nothing; breaking
parks it at position 3; resuming continues FROM there, which is why the second
pass yields the remaining 7 rather than all 10 or none.

Nothing is detected or optimised: CPython does no flow analysis and cannot know
a `break` is coming. `map` is simply DEFINED to return that object. Python 2's
`map` returned a list, exactly like ours — so the honest one-line statement of
this ticket is **we implemented Python 2's `map`**.

This also says what the divergence is NOT: not a missing optimisation, not a
perf gap. We return a different KIND of thing, and the difference is observable
whenever the consumer does not run to the end.

## What else cheats the same way — the scope of "build real objects"

In CPython these builtins are **classes**, so `map(f, xs)` is a CONSTRUCTOR call
and the value is an instance (which is why `print(x)` shows
`<map object at 0x...>`):

| | |
| --- | --- |
| classes | `map` `filter` `enumerate` `reversed` `zip` `range` `list` `dict` `set` `tuple` `str` `int` `float` `bool` `type` |
| functions | `len` `print` `sorted` `sum` `abs` `round` `repr` `isinstance` `getattr` `open` `iter` `next` |

pxx already models most of that class column properly — `list`/`dict`/`str`/
`tuple`/`set` are real types here (TPyList, TPyDict, …). The gap is only the
LAZY family, and it comes in two grades:

**Wrong KIND of value** — `map`, `filter`, `enumerate`, `reversed`, `zip`:
they are values, just eager lists instead of cursors. `z = zip([1],[2])` binds
fine and `list(z)` works; only laziness is missing. This is what options B and D
address.

**Not a value at all** — `range`. Measured:

| | pxx |
| --- | --- |
| `for i in range(3)` | works (a loop construct) |
| `list(range(3))`, `len(range(3))` | work (special-cased) |
| `r = range(3)` | **`undefined variable (range)`** |
| `range(3)[1]` | **`undefined variable (range)`** |

CPython's `range` is a lazy SEQUENCE — re-iterable, indexable, `len`-able — not
a cursor, so it is a different shape from the family above and would not be
fixed by an iterator protocol alone. It is also why `map(f, range(n))` does not
compile at all, which is what keeps the unbounded-memory case out of reach today.

Whoever takes this decision should know the two grades are separable: B or D
can land for the cursor family without touching `range`, and `range`-as-a-value
is its own (smaller, sequence-shaped) piece of work.

## The options

**A — Document it as a divergence.** Add it to
`devdocs/dev/nilpy-semantics-divergences.md` with the three shapes spelled out.
Cheap and honest — but it was the recommendation only while shape 2 read as a
memory/perf note. Now that shape 2 is measured as *an exception CPython never
raises*, documenting it means shipping a known upward-compatibility break, which
is the one thing the NilPy rule does not bend on. Keep A only as the interim
step that goes with D or B.

**B — Implement real lazy iterators.** Correct, and it also gives `iter()` /
`next()` somewhere to live (both are absent —
[[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]]). But it needs
an iterator protocol object in pylib, a frontend that can consume one in every
`for`/comprehension position, and a `__next__` dispatch — comparable in size to
the generator work, and it would touch the hottest loop lowering in the
frontend.

**C — Split the difference:** keep the eager list, but make `print`/`repr` of
one show CPython's `<map object at 0x…>` shape. This is the worst option and is
named only to be rejected: it makes the value LIE about what it is, so shape 3
gets more surprising, not less.

**D — Fuse them at the CONSUMPTION site (new, and the cheap correct one).**
The hazard lives entirely in `for x in map(f, xs):` — a loop that may stop
early. Lower that ONE shape as a fused loop (iterate `xs`, apply `f` per
iteration, evaluate the body) instead of building a list first. `list(map(...))`,
`sorted(map(...))` and a comprehension over one keep materialising, because
those consume everything anyway and cannot observe the difference. Same for
`filter` and `enumerate`; `reversed` needs no laziness at all, since its source
is already a materialised sequence.

This gets the break, the side effects and the raise right without an iterator
protocol, without `__next__` dispatch, and without touching the value's type —
`map(...)` in every other position stays the list it is today.

**What D does NOT fix, and it is not a corner:** binding first.

```python
m = map(risky, xs)
for n in m:          # a different statement — nothing to fuse
    ...
    break            # still eager, still raises
```

D keys on the syntactic `for x in map(...)`; once the call is bound to a name
the loop has no call to fuse, so that form keeps every symptom in this ticket.
Only real cursor objects (B) fix it. D is therefore the cheap fix for the
COMMON shape, not a complete one — and choosing it means saying so in the
divergences page, since the bound form is the shape a reader will reach for
next when the direct one starts behaving.

## Recommendation — REVISED after measuring shape 2

**D**, with **A** alongside it for what D deliberately leaves eager (a `map`
bound to a name and consumed twice, and the constant-factor memory), and **B**
revisited when generators land, since the two want the same machinery.

The earlier recommendation in this ticket was **A alone**. That was written when
shape 2 was described as "an unbounded or expensive source" — a perf note. The
measurement above changes the category: a program CPython accepts and runs
raises `ValueError` here, and no amount of documentation makes that acceptable
under the upward-compatibility rule. Recorded rather than quietly edited,
because the reasoning is the point: the shape was right and the severity was
guessed.
