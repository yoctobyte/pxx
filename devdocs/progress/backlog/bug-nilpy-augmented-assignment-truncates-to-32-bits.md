---
track: N
prio: 75
type: bug
summary: "NilPy: a binding initialised from a small int literal is typed 32-bit tyInteger, and `+=`/`-=`/`*=`/`<<=` KEEP that type and silently truncate — `c = 2000000000; c += 2000000000` prints -294967296, while the plain `c = c + 2000000000` is correct"
---

# NilPy augmented assignment silently truncates to 32 bits

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-06, bughunting, `tools/pydiff.py` against CPython.
- **Severity:** high. No bignums are involved — this is ordinary 64-bit integer
  arithmetic in the most ordinary Python code there is (an accumulator), giving
  a plausible wrong number with no error.

## Measured (self-hosted binary at `412fda7a3`)

```python
c = 2000000000
c += 2000000000
print(c)                 # CPython 4000000000     pxx -294967296

e = 100000
e *= 100000
print(e)                 # CPython 10000000000    pxx 1410065408

a = 1
a -= 3000000000
print(a)                 # CPython -2999999999    pxx 1294967297

a = 1
for i in range(40): a *= 2
print(a)                 # CPython 1099511627776  pxx 0

e = 1
e <<= 40
print(e)                 # CPython 1099511627776  pxx 0
```

Every wrong value is the correct value taken **mod 2^32**, read signed.

The plain spelling of the same operation is **correct**:

```python
d = 2000000000
d = d + 2000000000
print(d)                 # CPython 4000000000     pxx 4000000000   OK
```

Local and module scope behave identically (`f()` with `d = 1; d *= 100000;
d *= 100000` returns 1410065408).

## Cause — measured, not reasoned

`PXXDBG=n.locals` on the program above:

```
PXXDBG n.locals <module> a tk=1  ...     # a = 1              -> tyInteger  (32-bit)
PXXDBG n.locals <module> b tk=13 ...     # b = 5000000000     -> tyInt64
```

A binding initialised from a *small* int literal is typed `tyInteger`, which is
**4 bytes**. The plain form `d = d + x` re-infers the binding's type from the
whole RHS expression and widens it to `tyInt64`; the augmented form reuses the
existing 32-bit binding and truncates the result into it.

Confirmed by the complementary case: a binding whose FIRST assignment is already
wide (`b = 5000000000` -> `tk=13`) takes `b += 1` correctly. So the defect is the
binding's width, not the augmented lowering's arithmetic.

`compiler/pyparser.inc:16799` already records the tension this sits on: *"…
tyInteger, while an integer LITERAL token now reports tyInt64"*.

## Why 32-bit is the wrong default here

Python has no 32-bit int. NilPy's own promotable-int default (the whole point of
[[feature-a-promotable-int]]) is that an int binding widens rather than wraps —
which is exactly what the plain form does. `tyInteger` for a small literal is a
Pascal-shaped default leaking into a Python-shaped language, and augmented
assignment is where it becomes observable.

## Suggested direction

Type an int-literal-initialised NilPy binding `tyInt64` (or promotable), not
`tyInteger`, so both spellings agree. Whichever way it lands, **the invariant to
gate on is that `x op= y` and `x = x op y` produce the same value** — that
equivalence is what makes this findable and what a test should assert.

Note the related, distinct residual: `int("<30 digits>")` narrows to 64 bits —
[[bug-nilpy-int-of-a-long-decimal-string-narrows]] — and Variant-held bignums
narrow under `//`, `%`, ordering and `float()` —
[[bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum]].

## Gate

Per-fix loop (`make compiler/pascal26`, repro, `tools/gate.sh quick`). Add a
`.npy` test asserting `x op= y` == `x = x op y` across `+ - * << //` at values
straddling 2^31 and 2^63, diffed against CPython with `tools/pydiff.py`.
