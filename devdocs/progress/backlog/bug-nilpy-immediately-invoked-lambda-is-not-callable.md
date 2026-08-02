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

## 2026-08-02 — the three shapes MEASURED, and the cause named

The ticket asked for `(f if cond else g)(x)`, `handlers[k](x)` and
`obj.get_cb()(x)` to be measured before choosing a fix, on the grounds that if
they shared the path this was a symptom of something much larger. They do not all
share it, and the answer narrows the fix considerably:

| shape | result |
| --- | --- |
| `handlers["a"](2)` — dict subscript | **works** |
| `lst[0](3)` — list subscript | **works** |
| `f = lambda a, b: a - b` then `f(9, 4)` | **works** |
| `map(lambda v: v + 1, xs)` | **works** |
| **`(lambda a, b: a - b)(9, 4)`** | TypeError: object is not callable |
| **`(lambda: 7)()`** | does not parse |
| **`z = f if c else g` then `z(1)`** | does not parse |

Note the last row: `z = f if c else g` COMPILES on its own. Only the CALL fails.

### Cause

`PyBoxCallableValue` is what makes a callable value callable through a name: it
boxes the closure/bound-fn pointer into a variant so `z(...)` reaches the
dynamic-call path. It recognises exactly one shape — an `AN_CALL` straight to one
of `pyclosure_src_new` / `pyboundfn_new` / `pyboundfn_bind*`.

So it fires for `f = lambda ...` (the RHS *is* that call) and not for anything
that WRAPS such a call: a conditional expression whose arms are function values,
or a parenthesised lambda used directly as a callee. Subscripts work because they
go through a different path entirely — the container already holds boxed values.

### Consequence for the fix

Two independent pieces, and only the first is this ticket:

1. **The call site** must recognise a callable-valued EXPRESSION as a callee, not
   only a name. That covers `(lambda ...)(...)` and `(f if c else g)(x)` written
   inline.
2. **`PyBoxCallableValue` must see through wrappers** — at minimum a conditional
   whose two arms are both callable values, boxing the arms or the result. That
   is what makes `z = f if c else g` produce a `z` that can be called at all, and
   it is arguably its own ticket.

Neither needs the runtime-dispatch decision; both are compile-time shape
recognition, the same family as the unpack type-erasure fix (3ccb6576d).

## 2026-08-02 — the see-through-wrappers half is DEEPER than boxing. Attempted, reverted.

Tried the obvious version of item 2: teach `PyBoxCallableValue` to recognise an
`AN_TERNARY` whose both arms are callable and box the ARMS (boxing the arms
rather than the result, so only the selected arm still evaluates). It compiled
and changed nothing — `z = f if c else g` then `z(1)` still failed to parse.
Reverted rather than left in as dead code.

**Why it cannot work there.** The arms are not boxable calls in the first place.
A bare `def` NAME only becomes a function VALUE in a few specific positions —
`PyMakeFuncValue` is reached from the assignment RHS when the name is the whole
right-hand side, and from argument positions — so inside a conditional
expression, `f` never becomes a `pyboundfn_new` pair at all. There is nothing for
the boxer to see through.

So item 2 is really: **a bare def name in ANY value position should become a
function value**, and the ternary is just where that first shows. That is a
larger and more interesting change than "box a wrapper", and it probably
subsumes several sibling gaps (a def name in a container literal, in a return
expression, as a default). Whoever takes it should start by listing which
positions call `PyMakeFuncValue` today rather than by patching the boxer.

Item 1 (the call site accepting a callable-valued EXPRESSION as callee) is
untouched by this and remains the smaller, separable half — it is what
`(lambda ...)(...)` needs.
