---
summary: "NilPy survey: step slicing (x[::2]), list(range(...)), pow(), str.index/expandtabs, sorted(d.keys()) all fail to COMPILE — 13 of 133 method-surface cases"
type: bug
track: N
prio: 45
status: done
owner: claude-AN
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


## Resolved 2026-08-04 — 12 of 13; seven had already been fixed, five were new

Re-measured all 13 rows before touching anything. The survey was two-thirds
stale: step slicing (both list and str), `pow(2, 10)`, `str.index` and
`sorted()` over `.keys()`/`.values()` had all been fixed by other work since
2026-08-01. They are pinned in the new test rather than left uncovered — nothing
else was watching them.

| group | status |
| --- | --- |
| 1. step slicing (`x[::2]`, list and str) | already fixed |
| 2. `list(range(...))` — 5 cases | **fixed here** |
| 3. `sorted(d.keys())` / `sorted(d.values())` | already fixed |
| 4. `pow(2, 10)`, `"abcabc".index("c")` | already fixed |
| 4. `str.expandtabs` | **fixed here** |
| 4. `repr("ab")` | tracked in [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] |

### Group 2 — `list(range(...))`, and why it is scoped to `list(`

NilPy's `range` is not a value at all: it exists only as the counted-loop
lowering in a `for` header, which is why `for i in range(3)` worked and
`list(range(3))` said "undefined variable (range)". `pyrange_list` materialises
it, reached through `PyParseRangeList` when `PyRangeAsListWanted` sees that the
enclosing call is `list(`.

That gate is the design, not a shortcut. CPython's `range` is **lazy** and prints
as `range(0, 3)`, so materialising every range would have replaced a loud
compile error with a quietly different `print(range(3))` — trading a diagnostic
for a wrong value, which is the worse failure. `print(range(3))` therefore still
refuses to compile, deliberately, and the test says so in its header.

Bounds go through `PyUnboxRangeBound` for the same reason the `for` header does
— an unannotated parameter is a variant, and comparing against its box rather
than its value is what made `def f(n): for i in range(n)` loop forever. A zero
step raises `ValueError` inside `pyrange_list`, catchable, as CPython does.

### Group 4 — `str.expandtabs`

A tab advances to the next multiple of `tabsize` measured from the start of the
LINE, so the replacement width depends on the column and is not a fixed number
of spaces, and the column resets at `\n`/`\r`. `tabsize <= 0` drops tabs, as
CPython does. Sized-then-filled rather than built by concatenation, which is
quadratic here ([[project_pxx_string_concat_in_loop_is_quadratic]]).

Two arities, two proc NAMES (`pystr_expandtabs` / `pystr_expandtabs_n`) via a
new `wantArgs = -10` row, because `FindProc` is not arity-aware — the landmine
the `.format` row in the same table already carries a long note about.

### Verified

`test/test_nilpy_range_into_list.npy`, wired into `make test-nilpy`: all five
range rows plus empty/negative/variant-bound/zero-step cases, and eleven
`expandtabs` cases including tabsize 0 and 1 and an embedded newline. Diffed
against CPython, identical. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit 96152b221.
