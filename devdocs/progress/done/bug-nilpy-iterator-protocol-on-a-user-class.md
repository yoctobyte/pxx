---
prio: 35
track: N
type: bug
blocked-by: []
status: done
owner: agent-AN
---

# `for x in <user object>` does not use `__iter__`/`__next__`

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class Countdown:
    def __init__(self, n):
        self.n = n
    def __iter__(self):
        return self
    def __next__(self):
        if self.n <= 0:
            raise StopIteration
        self.n -= 1
        return self.n

for x in Countdown(3):      # CPython: 2 1 0
    print(x)
```

```
pascal26:11: error: Nil Python: pylib (count) not loaded
```

The for-loop lowering assumes a pylib container and looks for `count`. Re-
measured at HEAD 2026-08-09: unchanged.

## Why this is the biggest of the three siblings

It is not a name to bind but a protocol to teach the loop lowering: call
`__iter__` once, then `__next__` per step, and terminate on `StopIteration`
rather than on an index reaching a length. `StopIteration` as a control-flow
signal is the part with no existing analogue in the loop code — an exception
that must be caught by the LOOP, invisibly, and not propagate.

Generators (`yield`) are a different and much larger feature; this ticket is
only the explicit iterator-class protocol.

## Worth checking first

Whether the runtime dunder dispatch added 2026-08-08/09 (`PyFindDunder` +
`PyUserObjBoolDunder`/`PyUserObjObjDunder` in `pylib.pas`) can carry the
`__next__` call, so the loop lowering only has to emit the protocol and not
re-solve "find a method on a class known only at run time".

## Gate

`.npy` diffed against CPython: an explicit iterator class, one used twice
(a fresh `__iter__` each time), a class with `__iter__` but no `__next__`
(TypeError), and a control that iterating a plain list/dict/str is unchanged.

## Resolution (2026-08-15)

`for x in <user object>` walks `__iter__` once and `__next__` per step,
terminating on StopIteration — byte-identical to CPython, including CPython's
own TypeError wording for a class whose `__iter__` result has no `__next__`.

**The "worth checking first" note was right.** The runtime dunder dispatch does
carry it, so the loop lowering did not have to re-solve "find a method on a
class known only at run time":

- `PyUserObjNoArgDunder` (pylib) is the no-argument sibling of the existing
  `PyUserObjBoolDunder`/`ObjDunder` — same discipline of reading the return
  SHAPE out of the RTTI rather than assuming it, covering Variant (the
  unannotated `def __next__(self)`, which is how it is normally written), plus
  `-> int`, `-> str`, `-> bool`, `-> float` and a class return. Anything else is
  declined rather than called through an unchecked ABI.
- `pyiter_of_userobj` + a new `PYITER_USEROBJ` cursor kind reuse the whole
  existing cursor machinery, so the `for` desugar needed **one arm** and
  nothing about `continue`, `break`, `enumerate` or the pair unpack learned a
  third shape. The frontend change is 8 lines.

**StopIteration is caught in the cursor, not in the loop.** That is the part the
ticket calls out as having no analogue, and the answer was that it does not need
one: `pyiter_has` wraps the `__next__` call in `try … except on E: StopIteration`
and turns it into "exhausted", exactly as CPython's `for` does. Any other
exception propagates untouched — pinned by the `Angry` case in the test, which
raises ValueError from `__next__` and catches it outside the loop.

`pyiter_v` and `pylist_v` grew the same arm, so a user iterable reached through
a **Variant** works everywhere a cursor does. A statically typed receiver does
NOT — `list(b)`, `sorted(b)`, `sum(b)`, `x in b` still resolve against the
container overloads and answer `[]` or refuse. That is a call-site problem, not
a protocol one, and is filed as
[[bug-nilpy-builtins-over-a-user-iterable-answer-empty]] with the one-rule fix.

Found and filed on the way, pre-existing and independent (confirmed against the
pinned binary): [[bug-nilpy-raise-of-a-bare-exception-class-is-refused-at-runtime]]
— `raise StopIteration` without the call, which is how this ticket's own example
spells it, dies at run time. The test uses `raise StopIteration()` until that
lands.

**Gate:** `test/test_nilpy_iterator_protocol.npy` (+`.expected`, wired into the
Makefile) — the self-iterator, a separate iterator object re-iterated twice,
`break`/`continue`, a non-StopIteration raise escaping, the `__iter__`-without-
`__next__` TypeError, and controls that str/list/dict/`enumerate` iteration are
unchanged. All byte-identical to CPython. `tools/gate.sh quick` GREEN,
self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit 0ad42d2f4.
