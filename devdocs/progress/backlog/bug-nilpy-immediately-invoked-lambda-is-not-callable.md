---
track: N
prio: 55
type: bug
summary: "`(lambda a, b: a - b)(9, 4)` raises TypeError: object is not callable, and a zero-arg `(lambda: 7)()` does not even parse. The identical lambda bound to a NAME first is fine"
---

# An immediately-invoked lambda is not callable

- **Type:** bug (NilPy — runtime TypeError, and a parse error for the zero-arg
  form) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
print((lambda a, b: a - b)(9, 4))
# CPython: 5
# pxx    : Unhandled exception: TypeError: object is not callable (no __call__)

print((lambda: 7)())
# CPython: 7
# pxx    : error: unexpected token   (Kind 74)   <- does not even parse
```

## The control: binding it to a name FIRST works

```python
f = lambda a, b: a - b
print(f(9, 4))            # 5, correct
g = lambda: 7
print(g())                # 7, correct
print(list(map(lambda v: v + 1, [1, 2])))   # [2, 3], correct
```

So the lambda VALUE is built correctly and calling it through a name works, as
does passing it to `map`. Only calling the parenthesised lambda expression
directly fails — the value is produced and then not recognised as callable at the
call site.

That pins it on the call-site's callability test rather than on the lambda
lowering: `PyBoxCallableValue` boxes the closure when a lambda is the whole
right-hand side of an assignment (which is why the named form works), and the
parenthesised-expression call site has no equivalent step.

## Why it is worth fixing beyond the idiom itself

An immediately-invoked lambda is not everyday Python on its own, but the same
call site handles any *expression* that evaluates to a callable —
`(f if cond else g)(x)`, `handlers[k](x)`, `obj.get_cb()(x)`. If those share this
path they share the bug, and each of them IS everyday Python. Worth measuring
those three before deciding the fix's shape; if they already work, the fix is
narrow, and if they do not, this ticket is a symptom of a much larger one.

## Gate

A `.npy` diffed against CPython: the two repros; the named-lambda controls; a
lambda passed to `map`/`filter`/`sorted(key=)`; and the three expression-call
shapes above, whichever of them turn out to be affected.
