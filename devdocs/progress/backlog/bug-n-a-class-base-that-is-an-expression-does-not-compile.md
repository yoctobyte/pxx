---
track: N
prio: 45
type: bug
blocked-by: []
summary: "A class base which is a NAME bound to a type, or a call, does not compile: `B = object; class P(B)` fails where `class P(object)` and `class P(SomeClass)` both work. Blocks six.with_metaclass, which html5lib's parser spells as `class Phase(with_metaclass(...))` — the single remaining wall on html5parser.py."
---

# A class base that is an expression does not compile

- **Type:** bug (frontend) — **Track N**. Found from Track B, which cannot fix it.
- **Found:** 2026-08-17 by frank3, building `lib/rtl/mimic_six.py`
  ([[feature-nilpy-six-and-warnings-shims]]).
- **Measured against:** `pinned` **v345**. Not re-checked at HEAD.

## Repro — three cells, one variable

```python
class P(object):        # OK
    def hi(self): return "hi"
print(P().hi())
```

```python
class A:                # OK
    def hi(self): return "hi"
class P(A):
    pass
print(P().hi())
```

```python
B = object               # FAILS
class P(B):
    def hi(self): return "hi"
print(P().hi())
```

```
pascal26: error, near: B  object >>>   P
```

CPython runs all three. So a base which is a **class name** resolves, and a base
which is a **name bound to a type** does not — the same distinction that
`bug-n-a-type-name-is-not-a-first-class-value` fixed for ordinary value
positions, not yet extended to the base-class position.

A base which is a **call** fails the same way, which is the shape that matters
in practice:

```python
def wm(meta):
    return object
class P(wm(type)):      # FAILS
    pass
```

## Why it is worth more than it looks

It is the last wall on **`six.with_metaclass`**, and therefore on html5lib's
parser. `html5parser.py:426` reads:

```python
class Phase(with_metaclass(getMetaclass(debug, log))):
```

and `getMetaclass` (line 419) returns **plain `type`** unless the `debug` flag is
set. So the real, default path asks for *no metaclass at all* — semantically
just `class Phase(object)`, which this dialect can already express. The only
thing stopping it is that the base is written as an expression.

That is worth stating plainly because it changes the cost: supporting
`with_metaclass` here does **not** require metaclasses. It requires evaluating
the base expression. Metaclass support is only needed for html5lib's debug mode,
which the corpus scan does not exercise.

`lib/rtl/mimic_six.py` therefore refuses `with_metaclass` with a message naming
this ticket, rather than returning `object` — because returning `object` would be
semantically correct for the `meta is type` case and *still* would not compile at
the call site. The wall is the base expression, not the shim's answer.

## Gate

The third and fourth cells above compile and print `hi`. Then `mimic_six`'s
`with_metaclass` can return `object` for `meta is type` (and keep refusing
anything else, which genuinely does need metaclasses), and `html5parser.py`
advances past line 426.
