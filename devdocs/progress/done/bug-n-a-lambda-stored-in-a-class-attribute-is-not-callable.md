---
slug: bug-n-a-lambda-stored-in-a-class-attribute-is-not-callable
track: N
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, lambda, classes, callable]
blocked-by: []
summary: "`class gl: clear = lambda a: a * 3` then `gl.clear(2)` raises `TypeError: object is not callable` at run time; CPython prints 6. The same lambda bound to a MODULE-level name works (`f = lambda a: a * 3; f(2)` gives 6 in both), so it is the class-attribute store that loses the callable, not the lambda. Measured 2026-09-10 at compiler `98b6545b4652`. PRE-EXISTING and verified as such: it reproduces with and without the `staticmethod(...)` wrapper that was being added the same afternoon, so it is not that arm's doing -- the control without the wrapper fails identically. Compiles clean and fails at RUN time, which is the bad half: a class-as-namespace whose members are lambdas is accepted by the compiler and dies on first call."
---

# Measured

```python
class gl:
    clear = lambda a: a * 3
print(gl.clear(2))          # CPython 6; pxx TypeError: object is not callable
```

The control that says where it lives:

```python
f = lambda a: a * 3
print(f(2))                 # 6 in both
```

And the same shape through the new `staticmethod` arm behaves identically —
`clear = staticmethod(lambda a: a * 3)` also raises — which is what establishes
that the wrapper is not involved. A bare `def` name in the same position works
(`clear = add_one` then `gl.clear(1)` answers 2), so the difference is
specifically the lambda's boxed closure value reaching a class attribute.

# Why it compiles

`PyBoxCallableValue` is what makes a lambda callable through a name, and the
module-level assignment path calls it. The class-attribute store is a different
route. Two paths for one concept, and the one nobody extended is the one that
is broken — `normalise-dont-special-case`.

# What a fix must carry

Both doors, since they are separate: `gl.clear(2)` through the CLASS and
`gl().clear(2)` through an INSTANCE. Note the instance door has its own
open divergence for plain functions
([[bug-n-a-plain-function-as-a-class-attribute-does-not-bind-the-receiver]]),
so a lambda row there needs to say which behaviour it is asserting.

## Fixed 2026-10-02

PyEmitClassAttrExpr stored the lambda's closure pointer into the hidden
class-attribute global raw; the module-level `g = lambda` path boxes it with
PyBoxCallableValue, and the class-body path now does the same. While there,
`type()` of any def, lambda or bound method printed `<class 'NoneType'>`
(no builtin type code carried 'function' or 'method'); PYBT_FUNCTION and
PYBT_METHOD close that. Test:
test/test_nilpy_a_lambda_in_a_class_attribute_is_a_callable_function.npy
(HEAP_DEBUG and i386 rows, diffed against CPython).
