---
slug: bug-n-a-bound-method-stored-in-a-field-from-a-parameterised-receiver-is-not-callable
title: a bound method stored in a field is not callable unless the receiver was built from a literal
summary: >
  `self.cb = Tagged(tag).m1` in a constructor does not register `cb` as a
  callable field at all -- the compiler warns `no class declares a method or
  callable field .cb()`, falls to run-time dispatch on the receiver, and the
  call dies with `TypeError: object is not callable`. What decides it is whether
  the inner constructor's ARGUMENT is a LITERAL: `Tagged("B").m1` registers the
  field and works, while a parameter, a module global and `self.tag` all fail
  identically. Arity-independent -- it fails at ONE argument -- and reproducible
  on the pinned compiler, so it is not a consequence of the wide-arity fix that
  found it. CPython accepts all four spellings.
track: N
type: bug
prio: 40
owner: unassigned
status: open
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
