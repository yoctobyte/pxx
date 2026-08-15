---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`x.is_integer()` / `.hex()` / `.as_integer_ratio()` / `.conjugate()` work on a statically float receiver but raise AttributeError when the float arrives as a Variant — a loop variable, a list element, an unannotated parameter. `for v in vals: print(v.hex())` is the shape, and it is the ordinary one."
---

# float methods are invisible to the runtime method dispatcher

Filed 2026-08-15 while landing the float half of
[[bug-a-bytes-has-almost-none-of-its-python-methods]], which added the four
methods and their intercepts.

## Repro

```python
vals = [2.0, 0.1, 1e300]
for v in vals:
    print(v.hex())
```

```
Unhandled exception: AttributeError: 'float' object has no attribute 'hex'
```

The same call on a statically float name works and matches CPython exactly:

```python
z = 0.1
print(z.hex())      # 0x1.999999999999ap-4
```

## Why it is this way

The four float methods are claimed at the two intercept sites that KNOW the
receiver's static type (`PyIsFloatBaseTk`), and deliberately not by a name-only
test: `PyIsIntMethodSuffixAhead` sees a name and no receiver, and `hex` is
already a method of `bytes` — widening the name-only test would make every
generic postfix chain step aside for `b.hex()` and hand it to an intrinsic that
cannot serve it.

So the gap is exactly the VARIANT receiver, which goes to
`PyParseVariantMethod`'s runtime dispatcher. That dispatcher already has this
shape for str: a hoisted `pyvar_is_objtag(v) or pyvar_is_strtag(v)` guard plus
a per-tag arm (`smArmPossible` and the `smArmBuilt` fixup after it). The float
version is the same construction with a float-tag guard and an arm calling
`pyfloat_is_integer` / `pyfloat_hex` / `pyfloat_as_integer_ratio` /
`pyfloat_conjugate`, all four of which exist and are arity-0.

## Fix shape

Mirror the str arm in `PyParseVariantMethod` — do not invent a second
mechanism. The pylib side needs nothing beyond a `pyvar_is_floattag` predicate
beside `pyvar_is_strtag`; the four functions currently take a `Double`, so
either they gain Variant overloads or the arm unboxes with `pyvar_to_float`
first (the arm knows the tag, so the unbox is safe there).

Worth doing as ONE arm covering all four rather than per method: the dispatcher
is delicate AST surgery, and doing it four times is four chances to get the
hoist order wrong.

## Same statement about `int`

`(3).is_integer()` and `(3).as_integer_ratio()` are legal in CPython 3.12 and
are not intercepted here either — an int receiver takes neither the float path
nor an int-method path. Cheap to add alongside, and it belongs with this ticket
rather than as a third one.
