---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`B = object` is `undefined variable (object)`, while `t = str`, `u = int`, `v = dict` all bind and call fine. `object` is the single builtin type name that is not a first-class value — it is consumed as a no-op in the base-class position and has no row anywhere else, so any expression naming it fails."
status: done
---

# `object` is the one builtin type name that is not a first-class value

- **Type:** bug (frontend) — **Track N**.
- **Filed:** 2026-08-26, split out of
  [[bug-n-a-class-base-that-is-an-expression-does-not-compile]] while resolving
  it. That ticket's own 2026-08-19 re-measurement asked for this split: its
  headline repro (`B = object` then `class P(B)`) fails in the **assignment**,
  at line 1, and so was never an instance of the base-class bug it was filed
  under.
- **Measured at:** `dev` HEAD 2026-08-26, self-hosted fixedpoint build, and
  identically on pin **v375**.

## The boundary — one name, not a class of names

```python
t = str ; u = int ; v = dict     # all bind, and t("x") / u(3) call fine
B = object                       # error: undefined variable (object)
```

```
pascal26:1: error: undefined variable (object)
```

CPython binds all four. `str`/`int`/`dict` were made first-class by
[[bug-n-a-type-name-is-not-a-first-class-value]] (done); `object` was not, and
the gap is invisible from that ticket's tests because none of them name it.

## Why it is only this name

`object` has **no row anywhere**. Everywhere else it appears it is *erased
rather than resolved* — `PyParseClass` consumes `class C(object)` as a no-op
and sets `baseCi := -1`, deliberately, because "there is no `object` class to
point at and inventing one would put a real base in the chain that `super()`
and the method tables would then have to explain" (the comment at that site).

That call is right for the base position and does not generalise: in *value*
position there is nothing to erase to, so the name reaches ordinary lookup,
finds nothing, and reports an undefined variable. The other three names have
real backing classes (`TPyList` / `TPyDict` / `TPyBytes`, or the value types),
which is exactly why they could be made values and this one could not.

## Sizing — read this before starting

Not a missing arm on an existing chain; it needs a decision about what the
VALUE is. Options, in rising cost:

- **(a)** a `PYBT_*` builtin-type value for `object`, the way `type` already
  gets one (`PyMakeBuiltinTypeValue(12)` in the isinstance lowering). Cheapest,
  and enough for `B = object`, `isinstance(x, object)`, passing it around.
- **(b)** a real erased-shell class row. Bigger, and it re-opens precisely the
  `super()`/method-table question the base-position comment declines.

(a) is the recommendation: it matches how `type` is already handled and does
not disturb the base-class erasure.

## What it does NOT unblock

Worth stating so it is not re-derived. Fixing this does **not** make
`B = object` then `class P(B)` work end to end: the base position would then
have to erase an *alias to* `object` the way it erases the literal name, which
is a second, separate arm. And it does not move `six.with_metaclass` /
html5lib, which need a base that is a **call** — see the parent ticket's
"corpus argument does not hold" section.

## Gate

`B = object` compiles and the program runs; `t = str` / `u = int` / `v = dict`
keep working (they are the controls, and they pass today).

## Resolution (2026-11-11)

Measured first: `object()`, the sentinel idiom (`_MISSING = object()`),
was refused too, `undefined variable (object)`, and so was
`isinstance(x, object)`. That made this more than a value-position gap.

- pylib: `TPyObject` (a stateless class; Pascal reserves the word `object`)
  and `pyobject_new`. Type code `PYBT_OBJECT = 16`, named `object`.
  `pytype_name_v` answers `object` and the repr is CPython's
  `<object object at 0x..>`. `pybtype_call0` builds one (`B = object; B()`),
  and `pyisinstance_v` against the `object` type value is always True.
- Frontend: `object` in value position is the builtin type value
  (PyBuiltinTypeCode). `object()` calls `pyobject_new` unless the program
  binds the name itself. `isinstance(x, object)` goes to the runtime test.
  `class C(object)` was already accepted.

Identity, `==`, `dict.get(k, _MISSING) is _MISSING`, a def default, a class
attribute and a list of distinct sentinels all match CPython. Test
`test/test_nilpy_object_is_a_value_and_a_sentinel.py` (row `objsent26`).
