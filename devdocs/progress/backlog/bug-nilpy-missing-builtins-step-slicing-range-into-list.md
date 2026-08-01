---
summary: "NilPy survey: step slicing (x[::2]), list(range(...)), pow(), str.index/expandtabs, sorted(d.keys()) all fail to COMPILE — 13 of 133 method-surface cases"
type: bug
track: N
prio: 45
---

# Missing surface: step slicing, `list(range(…))`, `pow`, a few str/dict methods

- **Type:** bug (NilPy, unimplemented surface) — **Track N**
- **Opened:** 2026-08-01, from a differential sweep of the string/list/dict/
  builtin surface against CPython (133 cases, binary `c7d64813b`).

A **survey ticket**: found in one pass, but these are separate features. Split
per item when picked up. All fail LOUDLY (compile error), which is why this
ranks below the crashes and silent-wrong findings from the same sweep
([[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]],
[[bug-nilpy-str-format-ignores-positional-indices]]).

## Measured — 13 of 133 cases do not compile

| construct | CPython |
| --- | --- |
| `[1,2,3][::2]` | `[1, 3]` |
| `"abc"[::2]` | `ac` |
| `list(range(3))` | `[0, 1, 2]` |
| `list(range(1,4))` | `[1, 2, 3]` |
| `list(range(0,10,3))` | `[0, 3, 6, 9]` |
| `list(range(3,0,-1))` | `[3, 2, 1]` |
| `list(range(0))` | `[]` |
| `pow(2, 10)` | `1024` |
| `"abcabc".index("c")` | `2` |
| `"a\tb".expandtabs(4)` | `a   b` |
| `sorted({"a":1,"b":2}.keys())` | `['a', 'b']` |
| `sorted({"a":1,"b":2}.values())` | `[1, 2]` |
| `repr("ab")` | `'ab'` |

## Groupings, roughly by size

1. **STEP slicing** (`x[::2]`) for both list and str — 2 cases, one feature.
   Plain slices (`[1:]`, `[:2]`, `[-2:]`, `[::-1]`) all work today, so the
   grammar is there and the step is the gap. Note `[::-1]` DOES work, so
   reverse is special-cased rather than a general step.
2. **`range()` consumed by `list()`** — 5 cases. `for i in range(...)` works, so
   range exists as a loop construct but is not a value `list()` can take.
3. **`sorted()` over `.keys()` / `.values()`** — 2 cases. `sorted()` over a list
   works and `.keys()` works in a `for`, so this is the view-as-value gap, the
   same shape as (2).
4. **Individually missing builtins/methods** — `pow`, `str.index`,
   `str.expandtabs`, `repr`. `repr` is already tracked in
   [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]]; the other
   three are small and independent.

Note `str.find` works and returns the same answer `index` would — the only
difference is that `index` RAISES where `find` returns -1, so it is not merely
an alias.

## Gate (per split-out item)

`make test-nilpy` + self-host byte-identical, plus a `.npy` diffed against
CPython for that item, including its error cases (`index` on a missing
substring must raise `ValueError`; a step of 0 must raise; a negative step with
explicit bounds).
