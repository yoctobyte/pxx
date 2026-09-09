---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A class field assigned from a bare LOCAL of the same method -- `cx = 1.0` then `self.a = cx` -- was refused with `cannot infer the type of field self.a - annotate it`, and so was any expression built only from locals: `self.x0, self.z0 = cx - half, cz - half`. Every other spelling of the same binding already had an arm (a literal, a parameter, a module global, a global holding an instance, a global holding a def, None); the LOCAL was the one with none. `self.a = cx + 0.0` was accepted all along, because the literal operand types the expression -- which is what shows the operator was never the subject. lekkerzeilen chart.py:191. FIXED: PyRhsOnlyNamesThisMethodBinds + PyMethodBindsLocal, tyVariant, the same answer the bare-parameter arm gives."
status: done
owner: frankB
---

# A field assigned from a bare local of the same method has no inferable type

## The repro

```python
class C:
    def __init__(self):
        cx = 1.0
        self.a = cx          # cannot infer the type of field self.a

c = C()
print(c.a)                   # CPython: 1.0
```

Four lines, and the diagnostic asks for an annotation on a field whose value is
a float two lines above it.

## What discriminates

| spelling | before |
| --- | --- |
| `self.a = 1.0` | OK |
| `self.a = cx + 0.0` | OK -- the LITERAL types the expression |
| `self.a = t` (bare parameter) | OK -- it has its own arm |
| `self.a = self.b` | OK |
| `cx = 1.0` then `self.a = cx` | **refused** |
| `cx: float = 1.0` then `self.a = cx` | OK -- the annotation is read |
| `cx = 1` / `cx = "s"` then `self.a = cx` | **refused**, so not about float |

The type of the local is irrelevant. The one thing that fails is a bare name
the pre-pass cannot read a type off, and a local's inferred type does not
exist yet when the pre-pass runs -- `PyCollectModuleLocalsAST` has not run.

## Why it is the same family as five arms already there

`PyInferFieldDecl` is a ladder of readers, and each rung was added for a shape
that Python does not annotate: a qualified construction, a bare parameter,
None, a module-level literal, a module global holding an instance, a module
global holding a def. Every one of those has the identical blind spot -- the
name is bound somewhere the token scanners cannot type -- and every one was
answered rather than pushed onto the programmer. The method's own local was
the rung nobody had needed yet.

## The fix

`PyMethodBindsLocal` answers only "does this method bind this name", in the
four shapes Python binds one at statement level: `nm = ...`,
`nm, other = ...`, `for nm in ...` / `for a, nm in ...`, and `... as nm`.
`PyRhsOnlyNamesThisMethodBinds` accepts a right-hand side built only from
parameters and such locals. The field then takes tyVariant -- the same answer
the bare-parameter arm gives, and what an unannotated local carries anyway, so
the runtime tag travels with the value.

**A BINDING test and not a type reader, deliberately.** The diagnostic exists
to catch a typo, and a typo is not a parameter and not a local, so it still
fires. A CALL ends the scan as well: `self.v = f(cx)` is the expression
scanner's job and it types it correctly.

**`for` and `as` are ordinary IDENTIFIERS to this lexer** -- PyKeyword binds
only the words the Pascal side needs a distinct kind for. A test against
tkFor compiles and never fires. Found by writing one.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 57f494a94.
