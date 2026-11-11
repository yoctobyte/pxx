---
prio: 45
track: N
type: bug
status: backlog
owner:
blocked-by: []
summary: "A method call that omits a defaulted argument fills it from the STATIC callee's default, so when the call dispatches to a subclass override with a different default, the override runs with the base's value. CPython uses the override's own default."
---

# An override's own default is ignored when dispatched through the base

Found 2026-11-11 while extending `test_nilpy_duplicate_method_def.npy`.

```python
class F:
    def m(self, a, b=1):
        return "F " + str(a + b)
    def uses(self):
        return self.m(10)
class G(F):
    def m(self, a, b=2):
        return "G " + str(a * b)
print(G().uses())
```

```
CPython -> G 20
pxx     -> G 10      (G's body, F's default)
```

## Why

Omitted trailing arguments are filled at the CALL SITE from the
`ProcParamDefault*` arrays of the proc the call resolved to statically
(symtab.inc's shared call path). Inside `F.uses`, `self.m` resolves to `F.m`,
so `b=1` is pushed, and the virtual dispatch then lands in `G.m` with it.

## Possible fix

When the callee is virtual and some override in the hierarchy declares a
DIFFERENT default for a slot the call omits, fill that slot in the callee
instead: pass a "not supplied" marker and let each override's prologue apply
its own default. Only overrides whose defaults differ need it, which keeps the
ordinary path unchanged.
