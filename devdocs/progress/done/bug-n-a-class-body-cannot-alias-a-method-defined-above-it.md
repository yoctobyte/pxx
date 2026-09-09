---
slug: bug-n-a-class-body-cannot-alias-a-method-defined-above-it
track: N
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, classes, scoping, lekkerzeilen]
blocked-by: []
summary: "`__rmul__ = __mul__` in a class body fails with `undefined variable (__mul__)`: nilpy does not expose a method already defined in the same class body as an ordinary NAME in that body's namespace. Measured 2026-09-08 against compiler/pascal26 a7b03135f504. This one line in lekkerzeilen/math3d.py:54 blocks SEVEN of its sixteen runtime modules, because every one of them imports math3d. The diagnostic misleads: it reads as `operator overloading is unsupported` and that is false -- nilpy knows __mul__, __add__, __sub__, __truediv__, __neg__ and __eq__, and the same class compiles and gives CPython's answer once the alias line is deleted."
---

# Repro, with the control that separates the two readings

```python
class V:
    def __init__(self, x): self.x = x
    def __mul__(self, s):  return V(self.x * s)
    __rmul__ = __mul__          # pascal26: undefined variable (__mul__)
v = V(3) * 4
print(v.x)                      # CPython: 12
```

`./compiler/pascal26 probe.py out` -> `error: undefined variable (__mul__)`.
**Delete only the alias line and the identical class compiles and prints `12`.**
That control is what establishes this is a NAME-BINDING bug in the class body and
not a missing dunder — without it the obvious reading is "no operator
overloading", which would send an implementer at the wrong subsystem entirely.

`feature-nilpy-arithmetic-dunders-full-protocol` is `done/` and is not this: the
dunders resolve fine when called. What does not work is referring to one by name.

# Why it ranks above its one-line size

`name = earlier_name` in a class body is ordinary Python — it is how `__rmul__`,
`__radd__` and every other reflected operator is conventionally written, and how
`update = __init__`-style aliases are spelled throughout real code. It is not an
edge case reachable only by mistake, so it is squarely a compiler gap and
**the lekkerzeilen source should not move for it** (see the umbrella's cheat
rule, which permits changing that source and is deliberately not used here).

Blast radius is the argument: one line, seven modules, because it sits in the
vector-math module everything imports.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit bbd27a5c3.
