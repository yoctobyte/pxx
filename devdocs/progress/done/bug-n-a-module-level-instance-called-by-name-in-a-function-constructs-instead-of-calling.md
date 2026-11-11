---
slug: bug-n-a-module-level-instance-called-by-name-in-a-function-constructs-instead-of-calling
title: a module-level instance called by name in a function constructs instead of calling
summary: >
  `v(1.0)`, where `v` is a module-level instance of a class defining `__call__`,
  compiles to a CONSTRUCTOR call on that class when it appears as a top-level
  statement expression inside a function. It silently returns a new instance
  instead of the `__call__` result. The same expression is correct at module
  level, correct one block deeper (`if True: return v(1.0)`), correct as a
  sub-expression (`return v(1.0), 1`), and correct if the global is copied to a
  local first. Nothing in the matrix says the class name and the variable name
  need to be related, and case is not involved.
track: N
type: bug
prio: 58
owner: unassigned
status: done
---

## How it was reached

Answering the "worth checking in the same place" list at the end of
`bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`.
`__call__` was on that list and turned out not to belong to it: it fails with an
ordinary float literal too, so it is not the object-typed-operand bug and gets
its own file.

## Repro

One file, no imports, no lambda.

```python
class V:
    def __init__(self, x=0.0):
        self.x = x

    def __call__(self, a):
        return "CALL"


v = V(22.0)


def t1():
    return v(1.0)


def t3():
    if True:
        return v(1.0)
    return None


def t7():
    return v(1.0), 1


def verdict(tag, got):
    if isinstance(got, str):
        print(tag, "-> ok:", got)
    else:
        print(tag, "-> WRONG: constructed a V instead of calling __call__")


verdict("t1 bare return            ", t1())
verdict("t3 return inside `if True`", t3())
verdict("t7 in a tuple             ", t7()[0])
verdict("t8 module level           ", v(1.0))
```

## The table

`v` is a module-level `V(22.0)`; `__call__` returns the string `"CALL"`.

| shape | CPython | pxx @ c53d9ab55 |
| --- | --- | --- |
| `return v(1.0)` -- first def in the module | `CALL` | **new V** |
| `return v(1.0)` -- second def, identical body | `CALL` | **new V** |
| `x = v(1.0)` then `return x` | `CALL` | **new V** |
| `return v(1.0)` in a def that takes a parameter | `CALL` | **new V** |
| `r = None` first, then `r = v(1.0)` | `CALL` | **new V** |
| `if True: return v(1.0)` | `CALL` | `CALL` |
| `return v(1.0), 1` -- a tuple element | `CALL` | `CALL` |
| `v(1.0)` at module level | `CALL` | `CALL` |
| `f = v` first, then `f(1.0)` | `CALL` | `CALL` |
| instance created locally in the function | `CALL` | `CALL` |
| instance arriving as a PARAMETER | `CALL` | `CALL` |

Measured at c53d9ab55, compiler binary 2026-09-14, x86-64 `--threadsafe`.

Readings:

1. **The escape is nesting, not scope.** `if True: return v(1.0)` is the same
   expression in the same function reading the same global, one block deeper,
   and it is correct. So the name resolves correctly in that scope; something
   about the call appearing as a top-level statement expression in the function
   body picks the class instead.
2. **Being a sub-expression also escapes it.** `return v(1.0), 1` is correct.
   Together with (1) this looks like a resolution done at the statement level
   rather than the expression level.
3. **It is the GLOBAL that is required.** A local instance, an aliased local,
   and an instance arriving as a parameter are all correct. Only the
   module-level name is mis-resolved.
4. **Case is not involved.** I checked the obvious Pascal-host hypothesis --
   `v` versus `V` colliding in a case-insensitive symbol table -- and it is
   wrong: `inst = V(...)` and `gadget = Thing(...)`, names sharing nothing with
   their class, behave identically to `v` and `thing`. Recording the negative so
   nobody else spends a build on it.

## What it looks like when it bites

Silently, and then somewhere else. The first way I saw it was not a wrong value
but a runtime abort three lines later:

```
Nil Python: f-string format spec ".1f" on a value of variant tag 41 is not supported
```

which was `__repr__` running `"V(%.1f)" % self.x` on the wrongly-constructed
instance, whose `x` had been handed the call's argument through the wrong
signature. The reported error names a format spec in a method that is entirely
innocent; nothing points at the call site.

## Where to look

The call lowering for a bare `NAME(args)` statement expression in a function
body. The correct rows say the machinery exists and is reached from every other
position, so this reads like one arm resolving `NAME` against the type table
before the module-globals table, rather than a missing feature.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the eleven
rows above with expectations from CPython. The six correct rows matter as much
as the five wrong ones -- they are what localises the fix to the statement-level
arm instead of the call path.

## Log
- 2026-09-14 -- filed while sweeping the operator matrix for the object-typed
  operand bug. Reduction is single-file and inline above.

## Provenance

Measured and written by the peer session **lekkerzeilen-c8**, which cannot
commit in this checkout; this file is left untracked for that seat to pick up.

## Fixed 2026-11-10: it was the RETURN-TYPE inference, at two arms

The call lowering was right all along. The def's inferred RESULT type was wrong
(`PXXDBG=n.ret`: `t1 tk=6 rec=V`). A V-typed result for a str-returning
`__call__` made the caller treat the string as a V. That is why only shapes the
token scan types (a top-level `return v(...)`, or a local assigned from it)
failed, while `if True: return`, a tuple element and module level did not.

Two arms in PyInferExprType:

1. **The constructor arm case-folded.** `IsClassType('v')` answers for
   `class V`. It now requires PyIsClassTypeExact. So reading 4 ("case is not
   involved") was half right.
2. **The bare-name arm** typed `inst` by the class it holds, and the trailing
   `(...)` then kept that type. A call on an instance-typed name, which is not an
   exact class name, is now `__call__` and is typed as a variant.

Test: test_nilpy_a_module_level_instance_called_by_name_in_a_def.py, with the
table's rows plus an unrelated-name class and a constructor-then-field control.
