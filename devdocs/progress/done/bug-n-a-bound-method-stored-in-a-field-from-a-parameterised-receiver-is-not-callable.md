---
slug: bug-n-a-bound-method-stored-in-a-field-from-a-parameterised-receiver-is-not-callable
title: a bound method stored in a field is not callable unless the receiver was built from a literal
summary: >
  FIXED. `self.cb = Tagged(tag).m1` registered NO field unless the constructor's
  argument was a LITERAL -- a module global, a parameter and `self.tag` all
  failed identically, the call fell to run-time dispatch on the receiver, and
  died with `TypeError: object is not callable`. Arity-independent: it failed at
  ONE argument. PyCtorSelectorType chases `Foo()` through its trailing
  selectors and looked a selector up as a METHOD only when a `(` followed it,
  as a FIELD otherwise -- so a bound-method REFERENCE resolved to nothing and
  the chase answered tyUnknown. A bound method is a CALLABLE VALUE and travels
  as a variant, which is the rule PyInferExprType's own lambda arm already
  states; this is its third owner.
track: N
type: bug
prio: 40
owner: frankD
status: done
---

## How it was found

Writing the fixture for
bug-n-a-callable-attribute-dispatched-at-run-time-takes-at-most-4-arguments.
A bound method is one of the four carrier families that fixture has to cover,
and its row used `Tagged(tag).m5` to keep the tag visible in the output. That
row failed with `object is not callable` while the other three carriers passed.

**It was masked, not caused, by that ticket's cap.** With the four-argument cap
in place the same call reported `takes at most 4 arguments` instead, so the
real failure only becomes visible once five arguments are allowed through. At
one argument it is identical on the pinned and the fixed compiler.

## Repro

```python
# k.py
class Tagged:
    def __init__(self, tag):
        self.tag = tag

    def m1(self, a):
        return "m1:%s:%s" % (self.tag, a)


class Box:
    def __init__(self, tag):
        self.tag = tag
        self.cb = Tagged(tag).m1        # LITERAL "B" here and it works


def boxes(tag):
    return [Box(tag)]
```

```python
import k
xs = k.boxes("B")
print(xs[0].cb(1))
```

CPython prints `m1:B:1`. pxx warns `no class declares a method or callable
field .cb()` and raises `TypeError: object is not callable`.

The receiver must be reached through a CONTAINER, as above -- `o = k.Box("B")`
is typed statically and dispatches without consulting the field table.

## Measured, all at one argument, pinned compiler

| `self.cb = ...` | pxx |
| --- | --- |
| `Tagged("B").m1` — literal | `m1:B:1` |
| `Tagged(G).m1` — module global | `object is not callable` |
| `Tagged(tag).m1` — parameter | `object is not callable` |
| `Tagged(self.tag).m1` — own attribute | `object is not callable` |

## Where to look

The field-inference pass that decides what `FindUField` will see for a class:
it evidently records a field for `Tagged(<literal>).m` and records nothing for
`Tagged(<expr>).m`. The warning is emitted by the candidate scan in
pyparser.inc (`no class declares a method or callable field`), which is
CORRECT given an empty field table -- the defect is upstream of it, in what the
table was given. The run-time arm then does `pydynattr_get` and gets something
that is not a callable, so the second question is what that slot actually holds.

## Resolution (2026-09-18)

One arm, in `PyCtorSelectorType`: when `FindUField` misses, ask `FindUMeth`
before giving up, and answer tyVariant. `cur` becomes -1 because a callable
value has no class identity to chase a further selector through, so
`Tagged(tag).m1.something` is still refused by the loop's own `cur < 0` guard.

**Why the literal spelling worked, and why that was the misleading part.**
`Tagged("B").m1` is a different route through the CALLER, not a different answer
in this chase. The argument's value was never the subject -- what decided it was
only whether the chase resolved -- and an int literal worked too, which is what
ruled out any theory about strings.

**Measured, all at ONE argument, pinned versus fixed:** `Tagged("B").m1` and
`Tagged(7).m1` worked before and after; `Tagged(G).m1`, `Tagged(tag).m1` and
`Tagged(self.tag).m1` all raised `object is not callable` before and print
CPython's answer after. Binding off a local first (`t = Tagged(tag); self.cb =
t.m1`) is a different arm and always worked -- it is the fixture's control.

Fixture `test/test_nilpy_bound_method_field_from_expression.npy` (+
`boundmethodfield_mod.py`), every row at one argument so it pins THIS defect and
not the four-argument callable-field cap that was masking it. Refused by the
pinned compiler with the exact message above; byte-identical to CPython on the
fixed one. `callablefield_mod.py`'s bound-method row was switched back to the
parameterised shape it originally wanted, which now needs both fixes.

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 953456bf6.
