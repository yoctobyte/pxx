---
track: N
prio: 40
type: bug
blocked-by: []
summary: "A sweep of the builtin surface against CPython: `sorted(xs, key=None)` RAISES where CPython treats None as no key, a three-way `zip(a, b, c)` does not parse, and thirteen builtins are absent (frozenset, issubclass, callable, iter/next, slice, complex, format, ascii, eval, id, dir, vars, memoryview, max(default=))"
---

# Builtin surface gaps found by the 2026-08-12 sweep

- **Type:** bug / missing surface — **Track N**
- **Found:** 2026-08-12, sweeping every builtin against CPython one call at a
  time (the method [[feedback_sweep_operators_against_oracle_not_just_features]]
  recommends, applied to builtins).
- Companion to [[feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep]].

## 1. `key=None` raises — this one is a real defect, not a gap

```python
sorted([3, 1], key=None)     # CPython: [1, 3]
```

pxx raises:

> `TypeError: parameter key is not callable — the value is None (an import that
> did not resolve, or a name never assigned)`

CPython defines `key=None` as *"no key function"* — it is the documented
default, so passing it explicitly is legal and common when an optional key is
threaded through a helper (`def show(xs, key=None): return sorted(xs, key=key)`).
Same for `min`/`max`. The diagnostic is good and should stay for a genuinely
unresolved name; it just must not fire for the value None on `key=`.

## 2. `zip(a, b, c)` does not parse

```python
list(zip([1], [2], [3]))     # CPython: [(1, 2, 3)]
```

pxx: `error: unexpected token`. Two arguments work. Three-way zip is ordinary
(rows/labels/values), and the failure is at parse time.

## 3. A computed precision in a format spec does not parse

```python
n = 3
print(f"{7.5:.{n}f}")        # CPython: 7.500
```

pxx: `ValueError: unsupported format spec ".{n"` — the nested replacement field
inside the spec is taken literally. Every other spec form checked works
(width, alignment, fill, `e`/`g`/`x`/`o`/`b`, `,`, `+`, `!r`, `{{literal}}`,
subscripts and expressions inside the field), so this is the one hole in an
otherwise complete f-string surface. A computed precision is how a report makes
its decimal places configurable.

## 4. Absent builtins

Each is `error: undefined variable`, in rough order of how often real code
reaches for them:

| builtin | note |
| --- | --- |
| `iter()` / `next(it)` | `next(gen)` is how a generator is driven by hand |
| `callable(f)` | the standard "is this a function" guard |
| `issubclass(A, B)` | `isinstance` exists; its class-level twin does not |
| `type(x) == int` | `type(x)` is supported ONLY as `type(x).__name__` (its own diagnostic says so) |
| `format(v, spec)` | the function behind f-strings; the f-string itself works |
| `frozenset(...)` | `set` is complete otherwise |
| `max(xs, default=0)` | the empty-sequence guard |
| `id(x)` | identity |
| `complex(1, 2)` | no complex type at all |
| `slice(1, 2)` | slicing syntax works; the object does not |
| `ascii(x)`, `dir(x)`, `vars()`, `memoryview(b)` | rarer |
| `eval(s)` | deliberately absent? if so it belongs in the divergences page, not here |

Everything else in the sweep agreed: `hash`, `divmod`, `pow` (2- and 3-arg),
`repr`, `sum` with a start, `any`/`all`, `isinstance` with a TUPLE of types,
`bytearray`, and the whole `set` surface.

## Related but NOT a bug — eager iterators

`map`, `filter`, `reversed` and `enumerate` return LISTS rather than lazy
iterator objects, so `print(map(str, [1]))` prints `['1']` where CPython prints
`<map object at 0x...>`. Every ordinary use (`list(map(...))`, iterating it,
comprehending over it) agrees. It is a real semantic difference — code that
relies on laziness for an unbounded source, or on the iterator being consumed
once, would notice — so it belongs in `devdocs/dev/nilpy-semantics-divergences.md`
with that caveat spelled out, rather than in this ticket.

## Gate

A `.npy` diffed against CPython per item as it lands: `key=None` on
`sorted`/`min`/`max` (plus the existing diagnostic still firing for a genuinely
unassigned name), three- and four-way `zip`, and one asserting call per builtin
added.

## Item 1 DONE 2026-08-13 — `sorted(key=None)`; min/max still open

`sorted(xs, key=None)` sorts, in every spelling swept: explicit, with
`reverse=`, over strings, over a dict, over an empty list, and — the shape that
matters — threaded through a helper's own `key=None` default, both passed on
blindly and branched on with `if key is None`.

**Fixed at the coercion, keyed on the CALLEE'S DEFAULT.** A variant argument
heading for a `Pointer` parameter is coerced by `pyvar_callable_ptr`, which
raises on None. That is right for a parameter with no default — CPython refuses
`map(None, xs)` too, and the map row is in the test to keep it that way — and
wrong for `sorted(l; key: Pointer = nil)`, where nil ALREADY means "no key
function", which is exactly what CPython says `key=None` means. So the call
path now picks a None-tolerant twin when `ProcParamHasDefault` says the callee
declares one. Keyed on the declared default rather than on the parameter being
called `key`: the name is not what makes nil meaningful.

Test `test/test_nilpy_sorted_key_none.{npy,expected}`, wired into `test-nilpy`.

### Still open in item 1: `min`/`max` with `key=None`

`min([3, 1], key=None)` still raises `TypeError: expected a number, got
object`, and by a different mechanism — nothing to do with the coercion. It
picks the two-argument NUMERIC overload `min(const a, const b)` and compares
the list against None, the same mis-resolution `PyMinMaxByKey` already works
around for a callable held in a variable (it detects a callable second argument;
None is not callable, so it falls through). Whoever takes it should decide
between routing an explicit `key=` keyword at the frontend and widening that
runtime detection — `min(x, None)` positional is a TypeError in CPython, so the
runtime arm cannot simply treat a None second argument as "no key" without
turning that into a silently wrong answer.

## Item 4, first name DONE 2026-08-13 — `callable(x)`

Answers, matching CPython on every shape swept: a def, a lambda, a bound method,
an instance of a class defining `__call__`, a plain instance, ints / strs /
floats / None, all four containers, held in a variable, passed as an argument,
and used as a VALUE rather than only as an `if` condition.

Two halves, and only the first was free. `PyVarIsCallable` — the definition of
"callable" this unit already commits to for min/max's key detection — had been
in pylib all along and simply was not in the interface, so declaring it under
its Python name is the whole fix for functions and methods; no frontend
intercept. But it answers from the variant TAG, and an instance of a class with
`__call__` is an ordinary VT_OBJECT, indistinguishable there from a plain
instance, so that case asks the class RTTI (`PyFindDunder(cls, '__call__')`)
when the tag says object. The plain-instance row in the test is what keeps that
from degenerating into "any object is callable".

Test `test/test_nilpy_callable_builtin.{npy,expected}`, wired into `test-nilpy`.

**Noted, not fixed:** `callable(print)` and `callable(len)` do not PARSE — a
BUILTIN taken as a value, which is its own gap and unrelated to `callable`
(`print` as a bare name fails the same way anywhere). Not filed separately here
because [[bug-nilpy-small-builtin-surface-gaps-found-by-the-2026-08-13-sweep]]
already covers builtins-as-values for the str methods; worth folding in there if
it comes up again.

Still absent from item 4: frozenset (own ticket), id, slice, complex, format,
ascii, eval, dir, vars, memoryview, and `max(default=)`.
