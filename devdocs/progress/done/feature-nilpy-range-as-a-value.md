---
track: N
prio: 55
type: feature
blocked-by: []
owner: claude-N
summary: "range was NOT A VALUE — `r = range(3)` was `undefined variable (range)`, and `list(range(3))` worked only through a hard-coded whitelist of callees that promise to merely iterate their argument. TPyRange makes it CPython's lazy SEQUENCE: re-iterable, indexable, len-able, sliceable, constant-time membership, three Int64s and no storage."
status: done
---

# `range` as a value — a lazy SEQUENCE, not a cursor

- **Type:** feature (NilPy) — **Track N**
- **Opened / done:** 2026-08-12, straight after
  [[feature-nilpy-lazy-iterator-objects]], which explicitly put `range` out of
  its own scope: "it cheats differently — it is not a value at all, and
  CPython's is a lazy SEQUENCE (re-iterable, indexable, `len`-able), not a
  cursor."

## The fact

| | before |
| --- | --- |
| `for i in range(3)` | worked (a counted-loop lowering in the `for` header) |
| `list(range(3))`, `len(range(3))` | worked — **special-cased** |
| `r = range(3)` | **`undefined variable (range)`** |
| `range(3)[1]`, `print(range(3))` | **`undefined variable (range)`** |

The special case is the interesting half. `PyRangeIterConsumer` was a WHITELIST
of eleven callee names — `list`, `sum`, `len`, `sorted`, `tuple`, `set`, `any`,
`all`, `min`, `max`, `reversed` — each one a promise that the callee does
nothing but iterate its argument, so that MATERIALISING the range there was
invisible. Anywhere else the range stayed a compile error, deliberately: with
no range value to hand back, widening the rewrite would have turned a loud
error into a quiet `[0, 1, 2]` where CPython prints `range(0, 3)`.

That was the right call while there was no value. It stops being right the
moment there is one, and the whole mechanism is deleted here.

## Sequence, not cursor — the distinction is the design

Both are lazy, and that shared word is what made the two look like one problem.
They are not the same shape at all:

| | cursor (`map`, `filter`, …) | range |
| --- | --- | --- |
| iterate twice | second pass is EMPTY | yields the same values again |
| `len()` | `TypeError` | cheap and exact |
| indexable / sliceable | no | yes — and a slice is a RANGE |
| holds | a source + a position | three `Int64`s, no position at all |

So `TPyRange` is its own class beside `TPyIter`, and `iter(r)` hands back a
FRESH cursor every time — that is precisely what re-iterable means.

`range(10 ** 9)` is 24 bytes; `big[999999999]` is one multiply and
`999999998 in big` is one modulo. Membership is not a scan, which is the
property that makes a range worth having as a value rather than as a list.

## What was touched

- **pylib** `TPyRange` — `pyrange1/2/3` (ValueError on step 0), `pyrange_len`
  (CPython's formula, clamped at 0), `pyrange_at` (negative indexing +
  IndexError), `pyrange_contains` (one modulo), `pyrange_slice` (answers a
  RANGE), `pyrange_eq` (by the SEQUENCE, so every empty range equals every
  other), `pyrange_repr`, and `pyiter_of_range` — a new `PYITER_RANGE` cursor
  kind holding next-value / stride / count, with no source object at all.
  `at` is exposed as the DEFAULT PROPERTY, which is how indexing works with no
  new frontend mechanism: that is the shape the subscript path already calls.
- **Consumption**: `list`/`tuple`/`sum`/`any`/`all`/`len`/`iter`/`reversed`
  overloads, `sorted`/`min`/`max` in pyeval, plus the runtime arms in
  `pyvar_contains`, `pyvar_getitem`, `len(const v)`, `pylist_v`, `pyiter_v`,
  `sorted(const v)`, `min/max(const v)`, and all three rendering paths.
  Every one of them declared AFTER the existing overloads
  ([[project_nilpy_overload_declaration_order_decides_the_variant_unwrap]]).
- **Frontend**: the `range(...)` arm is now ungated and builds a TPyRange;
  `PyIsSliceBase`, `PyClassWantsIntIndex`, `PyIndexSeqKindCi`, the `in`
  dispatch, the `len()` arm and `PyMakeIterOf` all learned the class; `==` on
  two ranges lowers to `pyrange_eq` in `ir.inc` (it would otherwise be the
  pointer compare that `pylist_eq` exists to fix).
- **Deleted**: `PyRangeIterConsumer` + `PyRangeAsListWanted`.

## The unplanned deletion — one conversion instead of four spellings

`map`/`filter` picked their pylib entry by the iterable's static type
(`_l` / `_s` / `_i` / the variant one) through a helper, `PyIterCtorName`,
because those calls are built with `FindProc` and it is not overload-aware.
Range arrived as a FOURTH iterable shape — a sequence that is not a list — and
the picker would have needed to learn it.

That is the two-is-a-smell line from
`devdocs/dev/normalise-dont-special-case.md`. Instead the arms now call
`PyMakeIterOf` once and pass a cursor to a single entry, exactly as
`enumerate`/`zip` already did. `PyIterCtorName` and six pylib/pyeval spellings
are gone, and the new class needed no dispatch at all.

## What the `for` header still does

`for i in range(...)` is recognised in `PyParseFor` and keeps its COUNTED-LOOP
lowering — untouched. A range there is a loop bound, not a value, and lowering
it as an object would put a heap allocation where an induction variable
belongs. The value path is for the bound form (`r = range(n)` then `for i in r`),
which had no path at all before.

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` +
`make test-nilpy` + `stabilize-fast`/`pin`. Test:
`test/test_nilpy_range_as_a_value.npy`, diffed against CPython and wired into
`test-nilpy`.

## Log
- 2026-08-12 — resolved, commit PENDING-COMMIT.
