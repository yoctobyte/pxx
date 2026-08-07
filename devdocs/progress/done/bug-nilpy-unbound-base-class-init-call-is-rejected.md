---
track: A
prio: 55
type: bug
summary: "NilPy: `Base.__init__(self, n)` — the pre-super() spelling of a base-class constructor call, still ordinary Python — fails to compile with 'class method not found: __init__', because the ctor is registered under the name 'create' and the shared qualified-name path looks up the raw name"
status: done
owner: claude-A-N
---

# `Base.__init__(self, n)` is rejected: class method not found

- **Type:** bug (accepted-CPython program does not build) — **Track A**
  (file-ownership: the fix is in the SHARED `compiler/parser.inc`; the
  behaviour is Track N's)
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
class Base:
    def __init__(self, n):
        self.n = n
    def show(self):
        return "B%d" % self.n

class D(Base):
    def __init__(self, n, m):
        Base.__init__(self, n)      # <-- pascal26:9: error: class method not found: __init__
        self.m = m
```

Both neighbouring spellings **work**, which is what makes this a gap rather than
a missing feature:

- `super().__init__(n)` — fine.
- `Base.show(self)` — fine, the unbound **non-ctor** method call landed with
  [[bug-nilpy-super-and-unbound-parent-method-calls]]; that ticket covered
  `Parent.m(self)` and did not reach `Parent.__init__`.

## Root cause

`PyMethodName` (`compiler/pyparser.inc:17601`) registers `__init__` as
`create`. The qualified-name path in the shared `compiler/parser.inc` (~4423)
does `FindUMethOverloadAhead(ci, fieldName)` / `FindUMeth(ci, fieldName)` on the
**raw** field name, so `__init__` resolves to nothing and falls through to
`Error('class method not found: …')` at parser.inc:4567.

## The trap in the obvious fix — read before implementing

Mapping the name through `PyMethodName` and stopping there produces a **silent
wrong value**, which is worse than today's clean error. The resolved method is a
constructor, and the ctor branch (`UMthIsCtor` → `BuildMetaclassNew`,
parser.inc ~4570) sits **before** the PyExprMode unbound-call path (~4594). So a
bare rename would route `Base.__init__(self, n)` into the metaclass
*construct* path: it would allocate a **fresh** Base, run the ctor on that, and
discard it — leaving `self.n` never initialised, with no diagnostic.

The fix has to reach the unbound path instead: `X.__init__(self, args)` must
lower to a direct, non-virtual call of X's ctor **body** with the existing
`self` as receiver — exactly what the PyExprMode block at ~4594 already does for
`Base.show(self)`, and semantically what `super().__init__` already lowers to.
Gate the whole thing on `PyExprMode` so the Pascal frontend's
`TFoo.Create(...)` metaclass behaviour is untouched.

Note `X` need not be the direct base (cooperative/mixin code names a
grandparent, or an unrelated class), so this is not simply a rewrite to
`super()`.

## Gate

Track A gate: `make compiler/pascal26` (IS the byte-identical self-host
fixedpoint) + `tools/gate.sh quick`. A `.npy` test covering
`Base.__init__(self, …)` from a direct subclass, a grandparent named across two
levels, the `super().__init__` form and `Base.show(self)` (both must stay
correct), and — the point of the trap above — an assertion that the base
ctor's writes landed on `self` rather than on a discarded instance. Diffed
against CPython with `tools/pydiff.py`.

## Log
- 2026-08-07 — resolved, commit db43ea06d.
