---
track: N
prio: 50
type: bug
status: done
owner: claude-AN
---

# Three loud gaps found by the CPython differential sweep

- **Type:** bug / missing builtins (NilPy) — **Track N**
- **Found:** 2026-08-02, by `tools/pydiff.py run` over a str/list/dict surface
  probe, alongside [[bug-nilpy-percent-r-renders-as-str-not-repr]].

All three are **loud** — a compile error or a runtime raise — so they are the
good case, unlike the `%r` bug found in the same sweep. Grouped because they are
small and share a discovery.

## 1. `pow()` is undefined

```python
print(pow(2, 10))     # CPython 1024
```
```
error: undefined variable (pow)
```

`**` works, so this is the missing builtin wrapper, not the operation. The
three-argument `pow(base, exp, mod)` form is worth covering at the same time —
it is the one people reach for in modular arithmetic and is not expressible as
`**`.

## 2. `"{:,}".format(n)` — thousands separator unsupported

```python
print("{:,}".format(1234567))     # CPython 1,234,567
```
pxx raises `Nil Python: unsupported f-string format spec ","` at RUN time and
**aborts the program**, so everything after it is lost. Two things to decide:
whether to implement `,` (and `_`), and separately whether an unsupported spec
should raise a catchable error rather than abort — the latter matters more,
since it is the same "must be catchable" principle already applied to
missing-operator cases.

## 3. Stepped slices other than `[::-1]`

```python
print("abcdef"[1:5:2])     # CPython bd
```
```
error: Nil Python: only the whole-range reverse slice [::-1] is supported;
       other steps are not implemented
```

An honest, explicit diagnostic — recorded so the gap is tracked rather than
rediscovered by the next sweep.

## Gate

Per item, a `.npy` diffed against CPython. For 1: `pow(2,10)`, `pow(2,10,7)`,
and float/negative exponents. For 2: `{:,}` on int and float, plus the
abort-vs-raise decision. For 3: forward and negative steps, and slices with a
step on both str and list.


## 2026-08-02 — two more from later sweeps

4. **`tuple(iterable)` is undefined** — `tuple([1, 2])` gives
   `undefined variable (tuple)`. The tuple TYPE exists (literals work, and
   `FIsTuple` distinguishes it), so this is the missing constructor wrapper,
   the same shape as `pow()` above. Found alongside
   [[bug-nilpy-derived-tuple-loses-tupleness]].

5. **`range` as a VALUE** — `list(range(3))` gives
   `undefined variable (range)`. `range` works as a for-loop header only; it is
   not a first-class object. `list(range(n))` is an extremely common spelling.
   Found alongside [[bug-nilpy-range-over-a-variant-bound-loops-forever]].


## 2026-08-02 — items 1 and 4 FIXED

**`pow()`** and **`tuple()`** are done, both as small additive builtins in
pylib, verified byte-identical to CPython in
`test/test_nilpy_tuple_pow_builtins.npy` (wired into `make test-nilpy`).

- `tuple(l: TPyList)` and `tuple(const s: AnsiString)` — the same sequence with
  `FIsTuple` set, so `tuple([1,2])` prints `(1, 2)` and composes correctly with
  the derived-tuple work (`tuple([1,2]) + (3,)` is a tuple).
- `pow(a, b)` delegating to the existing `pypow_v`, which already backs `**`.

**`pow(base, exp, mod)` deliberately NOT added.** Modular exponentiation is a
different algorithm, and accepting a third argument while ignoring the modulus
would be silently wrong — exactly the failure mode this repo treats as worst. It
stays a loud "no overload of pow matches these arguments" until someone
implements it properly.

## 2026-08-02 — item 2 FIXED (both halves)

`"{:,}"` is implemented in **both** the int and the float overload in pylib, and
the two unsupported-spec sites now `raise ValueError` instead of `Halt(1)` — so
the abort-vs-raise half is done too, and a `try/except` around a format now
actually runs. Verified byte-identical to CPython in
`test/test_nilpy_format_thousands.npy` (wired into `make test-nilpy`).

A third divergence surfaced while writing the test and is fixed with it: a float
spec naming **no type and no precision** is Python's *general* form, not
fixed-6 — `"{:,}".format(1234.5)` is `1,234.5`, was `1,234.500000`.

`_` as a separator is NOT implemented; it stays a loud raise.

## 2026-08-02 — item 3 FIXED

Extended slices `xs[lo:hi:step]` work for any non-zero step on str, bytes, list,
tuple and a variant holding any of them (`81153f008`). Bounds are CPython's
`slice.indices()`, added as `PySliceBoundsStep` beside `PySliceBounds` rather
than folded in — with a negative step the omitted defaults AND both clamps
differ. Verified with a 150-case lo/hi/step sweep vs CPython;
`test/test_nilpy_slice_step.npy` (33 lines) is in `make test-nilpy`.

The `[::-1]` special case (a rewrite to `reversed()` / `pystr_reverse`) is gone,
which fixed tuple reversal for free: `reversed()` yields a list, while
`pylist_slice_step` carries `FIsTuple` across.

Not implemented, and refused BY NAME rather than approximated: assigning to an
extended slice (`l[::2] = ...`) and `del l[::2]`. Dropping the step there would
touch the wrong elements.

## 2026-08-02 — item 5 scoped (NOT started), so the next session need not re-scope

`range` as a value is a new TYPE, not a missing wrapper like `pow`/`tuple` were,
and it is the only item here that is not a quick fix. Measured state: `range`
works ONLY as a for-loop header (a counted-loop lowering, `PyParseForIn`); in
any expression position it is `undefined variable (range)` — including
`list(range(3))` and `sum(range(5))`.

**Do not implement it by materialising a TPyList eagerly.** That is the obvious
20-minute version and it lies in three observable ways: `print(range(3))` would
give `[0, 1, 2]` instead of `range(0, 3)`, `type(range(3)).__name__` would give
`list`, and `range(10**9)` would exhaust memory instead of being O(1). Silent
wrong values are exactly what this repo refuses; the current loud compile error
is strictly better than that, which is why this is NOT urgent despite `range`
being common.

The honest shape is a `TPyRange` class in pylib (FStart/FStop/FStep + count/at)
plus, at minimum: `list()` / `len()` / `sum()` overloads, indexing, `==`,
printing through the variant object path, and a for-in arm. Iteration may
legitimately materialise at the loop (`pyrange_to_list`) — that costs only the
huge-range case and keeps every observable answer right, whereas materialising
at CONSTRUCTION corrupts print and type().

Note the interaction: for-in over a VARIABLE holding a range goes through the
generic variant path, so `pyvar_*` needs a TPyRange arm too, not just the
static one.

## Still open
5. `range` as a first-class VALUE (`list(range(3))`).

## 2026-08-02 — a fourth loud gap, same family: NESTED format specs

```python
w = 7
print(f"{n:{w}d}")     # CPython: "     42"
                       # pxx    : ValueError: unsupported format spec "{w"  (at RUN time)
```

A format spec may itself contain a replacement field — that is how a width or
precision is computed rather than written literally, and it is the standard way
to build a table whose column width is decided at run time.

Same shape as the `,` thousands-separator gap above: **loud, and raised at RUN
time for something knowable while compiling.** The spec text is a literal in the
source; a spec pxx cannot handle could be refused when the f-string is parsed,
naming the file and line, instead of surfacing as a ValueError from somewhere
inside the program.

That is worth doing for the whole family at once rather than per spec — it turns
"my program died halfway through" into "line 14 uses a format spec pxx does not
support yet", which is the difference between a bug report and a five-second fix.

### What the same sweep confirmed WORKS, for scope

Measured byte-identical to CPython in the same run, so the f-string machinery is
in good shape and this really is a spec-parser gap:
`{n:5d}`, `{n:<5}`, `{n:>5}`, `{n:^5}`, `{f:.2f}`, `{f:8.3f}`, `{f:e}`,
`{n:x}`, `{n:o}`, `{n:b}`, `{n:+d}`, `{-n:+d}`, `{0.5:.0%}`, `{s!r}`, `{n!r}`,
`{{literal}}`, expressions inside holes (`{n + 1}`, `{s.upper()}`, `{len(s)}`),
subscripts (`{xs[0]}`, `{d['k']}`), a nested string literal (`{'nested'}`),
`"%s-%d" % (s, n)` and `"{0} {1} {0}".format(...)`.


## Resolved 2026-08-04 — two of the three had already been fixed; `pow` finished

Re-measured all three before touching anything, and the ticket was two-thirds
stale:

| item | today |
| --- | --- |
| 2. `"{:,}".format(1234567)` | **already works** — `1,234,567` |
| 3. `"abcdef"[1:5:2]`, `[1,2,3,4,5,6][1:5:2]`, `"abcdef"[::2]` | **already work** |
| 1. `pow(2, 10)` | already works |
| 1. `pow(2, 10, 1000)` | **still `no overload of pow matches these arguments`** |

Items 2 and 3 were fixed by other work since 2026-08-02 (`pystr_slice_step` and
the format-spec handling). They are pinned in the new test rather than left
untested, since nothing else covered them.

### `pow(base, exp, mod)` implemented

Modular exponentiation, and genuinely a different algorithm rather than
`(a ** b) mod m` — the intermediate power overflows long before the modulus
does, which is the whole reason Python has the three-argument form. Three
things it gets right that are easy to get subtly wrong, each pinned by a row:

- **The result carries the sign of the MODULUS.** `pow(2, 3, -5)` is `-2`, not
  `3`. That is Python's floored-modulo rule, and it is not what a plain `mod`
  produces.
- **A negative exponent is the modular INVERSE** raised to `|exp|` (CPython
  3.8+), by extended Euclid, raising `ValueError` when the base is not coprime
  with the modulus — which is what CPython raises too. The first version refused
  negative exponents outright; measuring against the oracle showed CPython
  answers `pow(2, -1, 5)` = `3`, so the refusal would have been a real gap and
  was replaced.
- **Products are accumulated by doubling** (`PyMulMod`), because a plain `a * b`
  overflows Int64 once the operands pass 2^31 even though the *result* is
  bounded by `m`. Every intermediate then stays below `2m`, which is why the
  modulus is capped just under 2^62 and refused loudly above it rather than
  silently wrapping.

`m = 0` raises `ValueError`, as in CPython, and both raises are catchable — the
"must be catchable, not an abort" principle this ticket's item 2 raised.

### Verified

`test/test_nilpy_pow_mod.npy`, wired into `make test-nilpy`: 20 `pow` values
including both negative-modulus and negative-exponent cases and a 2^62 modulus,
both error paths, plus the items 2 and 3 regressions. Diffed against CPython,
identical. `tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit 93fa036fd.
