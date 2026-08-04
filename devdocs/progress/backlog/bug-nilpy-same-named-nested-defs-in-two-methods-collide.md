---
track: N
prio: 45
type: bug
summary: "Two methods of one class cannot both declare a nested def of the same name — the second call binds the first method's def and fails on arity. Pre-existing; loud."
---

# Two methods of one class cannot both have a nested def of the same name

- **Type:** bug (NilPy — compile error on valid code) — **Track N**
- **Found:** 2026-08-04, writing the regression test for
  [[bug-nilpy-nested-def-capturing-self-called-from-a-sibling-returns-nothing]],
  where every method naturally wanted a nested def called `draw`.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`.

## Repro

```python
class C:
    def a(self):
        def draw(v):
            return v + 1
        return draw(10)
    def b(self):
        def draw():
            return 99
        return draw()
c = C()
print(c.a(), c.b())     # CPython: 11 99
```

```
error: ...
  candidates:
    draw(Variant)
  near:    draw
```

The zero-argument `draw()` in `b` is matched against `a`'s one-argument `draw`,
so the two nested defs are not being kept apart. **Loud**, which is the good
case — it is a compile error, not a wrong value.

## Where to look

Nested defs register under a qualified name via `PyQualifyNested` /
`PyNestPrefix`, and a method's prefix is its full `Class.method` name
(`PyNestPrefix := fullName` in the method path), so `C.a.draw` and `C.b.draw`
should already be distinct. So the collision is more likely in the LOOKUP than
in the registration: `PyQualifyNested` walks the prefix outward and stops at
the first `FindProc(pfx + '.' + name)` that hits, so if the prefix in force at
the call site is not the calling method's own, the walk can reach the other
method's def. Worth dumping both registered names first (`PXXDBG=n.caps` lists
them qualified) before assuming which half is wrong.

Note two nested defs of the same name in two plain FUNCTIONS do NOT collide —
`def f(): def draw(v): ...` beside `def g(): def draw(): ...` compiles — so this
is specific to methods.

## Gate

A `.npy` diffed against CPython: the repro; the same with matching arities (so
the failure cannot hide behind overload matching); the two-plain-functions
control; and a third method adding a same-named nested def, to confirm the fix
scales past two.
