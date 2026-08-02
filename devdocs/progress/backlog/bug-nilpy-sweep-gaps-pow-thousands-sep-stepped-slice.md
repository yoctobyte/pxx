---
track: N
prio: 50
type: bug
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

## Still open

2. `"{:,}"` thousands separator — unsupported, and it ABORTS rather than raising
   catchably. The abort-vs-raise half matters more than the feature.
3. Stepped slices other than `[::-1]`.
5. `range` as a first-class VALUE (`list(range(3))`).
