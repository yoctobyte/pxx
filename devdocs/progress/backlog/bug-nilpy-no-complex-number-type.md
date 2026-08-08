---
prio: 15
track: N
type: bug
blocked-by: []
---

# NilPy has no complex number type

- **Type:** bug / missing type (NilPy) — **Track N**
- **Found:** 2026-08-09, while making
  [[bug-nilpy-pow-and-log-hang-on-a-non-positive-base]] refuse instead of hang.
- **Loud** since that fix: a named `ValueError`, not a wrong real number.

```python
print((-8) ** (1 / 3))    # CPython (1.0000000000000002+1.7320508075688772j)
                          # pxx     ValueError: ... is complex, which NilPy does not have
print(complex(1, 2))      # CPython (1+2j)
print(1j)
```

`complex` is a Python builtin type, so this is a genuine upward-compatibility
gap: a program CPython accepts and runs does not run here.

## Why it is prio 15 anyway

Complex arithmetic appears in almost no application code outside numerics, and
the one place it turns up by ACCIDENT — a negative base raised to a fractional
power — now raises a clear, named error rather than hanging or inventing a real
number. So the cost of not having it is a loud refusal in a rare spot.

`lib/rtl/ucomplex.pas` exists on the Pascal side, which is a starting point if
this is ever picked up: the type and its arithmetic exist, and the work would be
the NilPy surface (the `j` literal suffix, `complex()`, `.real`/`.imag`, repr,
and the arithmetic dunder routing) rather than the maths.

## Gate
`.npy` diffed against CPython: a `1j` literal, `complex(a, b)`, `.real`/`.imag`,
repr of several values, arithmetic between complex and int/float, and
`(-8) ** (1/3)` giving CPython's value.
