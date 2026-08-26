---
track: N
prio: 80
type: bug
blocked-by: []
summary: "A class base which is a NAME bound to a type, or a call, does not compile: `B = object; class P(B)` fails where `class P(object)` and `class P(SomeClass)` both work. Blocks six.with_metaclass, which html5lib's parser spells as `class Phase(with_metaclass(...))` — the single remaining wall on html5parser.py."
status: backlog
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


---

## RE-MEASURED at HEAD 2026-08-19 — not fruit, and the ticket's own repro misdiagnoses it

Re-measured because the ticket said "Measured against pinned v345, not
re-checked at HEAD". Still reproduces, but it is **three separate defects**, and
the headline repro is not an instance of the bug the title names.

| shape | result | what it actually is |
| --- | --- | --- |
| `B = object` then `class P(B)` | `undefined variable (object)` **at line 1** | fails in the ASSIGNMENT — `object` is not a first-class value. Nothing to do with the base position. |
| `B = A` then `class P(B)` | `unknown base class B` | the real base-position bug |
| `class P(pick())` | `unknown base class pick` | base is an arbitrary call |
| `class P(A)` | OK | control |

Two controls that decide the sizing:

```python
B = A ; print(B().hi())                       # WORKS
B = A if len(sys.argv) > 99 else C            # a RUNTIME-chosen alias
print(B().hi())                               # WORKS -- prints C, like CPython
```

A class held in a variable is a genuine **run-time** value (a metaclass blob),
resolved when it is called. There is therefore **no compile-time record that
`B` means class `A`** — and a base class is needed at compile time, because it
determines the layout and the vtable.

So the fix is not an extra arm in the base-name chain
(`pyparser.inc:32370-32403`, which is pure name lookup: Exception, qualified,
FindUClassNonRecord, PyBuiltinBaseCi, error). It is either:

- **(a)** a new compile-time constant-alias analysis — "this module-level name is
  bound once, to a class literal, and never rebound"; or
- **(b)** run-time class creation, for the general case.

Both are mechanisms. Parking rather than starting one.

## The corpus argument in the summary does not hold

The frontmatter says this "blocks six.with_metaclass, which html5lib's parser
spells as `class Phase(with_metaclass(...))` — the single remaining wall on
html5parser.py". Checked:

```python
# html5lib/html5parser.py:426
class Phase(with_metaclass(getMetaclass(debug, log))):
```

That is the **call** shape, and its argument depends on a run-time flag, so it
needs (b) — the harder half. Option (a), the tractable half, would not move
html5parser.py at all. `lib/rtl/mimic_six.py:97` already reaches the same
conclusion and deliberately raises rather than pretending.

Also worth recording so it is not re-derived: **html5parser.py's current first
wall is not this at all.** At HEAD it stops on `decode has no parameter named
'final'` ([[bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name]]),
which is upstream of the base-class question. So even (b) would not make
html5parser.py compile today, and the "single remaining wall" claim is stale.

Leaving prio at 45. Suggest splitting out the `object`-as-a-value defect, which
is unrelated to this title and may be much cheaper.
