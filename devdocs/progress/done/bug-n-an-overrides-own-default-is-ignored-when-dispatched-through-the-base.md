---
prio: 45
track: N
type: bug
status: done
owner: rd
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

## Fix (2026-11-20, rd)

`PyOverrideAwareDefault` (pyparser.inc) works per omitted argument of a
virtual NilPy method call:
- It collects every class below the method's owner that overrides the same VMT
  slot.
- When any of them declares a different default for that slot, it builds
  `<G's default> if recv is G else ... else <F's default>`. AN_TERNARY over
  AN_IS_TEST, deepest class first, so the nearest override on the receiver's
  chain wins.
- When no override changes the default, it answers -1, and the ordinary single
  node is built exactly as before.

**One rule for every spelling of a method call:** the shared `FillDefaultArgs`
asks it through a frontend trampoline (`FrontendOverrideAwareDefault`,
pyforwards.inc, -1 without NilPy). So does PyParseClassMethodCall's own fill.

**Left on the old static default, by design:**
- a receiver that is not a pure designator, because it would be evaluated
  twice;
- defaults of different kinds across the family, because one conditional's
  arms must share a type;
- an override in a module compiled after the call site, which is not
  registered yet. See feature-n-register-every-module-s-classes-before-any-module-s-methods-are-typed.

**Test:** test-nilpy row ovdflt26,
`test_nilpy_an_override_s_own_default_applies_through_the_base.py`. Its
.expected is CPython's output. It covers an int default, a str default, a
grandchild with the parent's default, an inheriting subclass, a same-default
override, and explicit calls. The compiler before the fix prints `G 10 G:f` /
`H 9 G:f` where CPython prints `G 20 G:g` / `H 8 G:g`.

**Side observation:** the -dPXX_NO_NILPY build of the compiler is already
broken at origin/master: 21 errors, undefined PyIsClassTypeExact, PyMakeIdent,
PyMakeNone, and others. This change adds none; the error set is identical
before and after.
