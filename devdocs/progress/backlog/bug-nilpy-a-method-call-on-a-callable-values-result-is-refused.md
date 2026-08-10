---
summary: "`g(3).show()` — a selector on the RESULT of calling a callable VALUE is a parse error (`expected expression`). Binding the result first (`o = g(3); o.show()`) works, so only the chained arm is broken. Applies to any callable value: a def taken as a value, and now a class."
type: bug
track: N
prio: 50
found-by: claude-AN
---

# A method call on a callable value's result is refused

- **Type:** bug (parse error on valid Python) — Track N
- **Opened:** 2026-08-10
- **Found by:** the gate cases for [[feature-nilpy-class-as-a-value]], where
  every `cls(3).show()` had to be rewritten to two statements.

## Repro

```python
class A:
    def __init__(self, v): self.v = v
    def show(self): print("A", self.v)

def mk(v):
    return A(v)

g = mk
g(3).show()
```

CPython prints `A 3`. pxx:

```
pascal26:11: error: expected expression
  near: mk  g    >>>  show
```

Confirmed pre-existing at `pinned`, and NOT specific to classes — `g` here is an
ordinary def taken as a value. `o = g(3); o.show()` works, so the call and the
method both work; only the chain is refused.

## Shape

The variant-callee call (`pyvar_callvN`) is built where the expression parser
does not go on to accept a selector on its result. Pascal had the mirror image
of this on the STATEMENT side twice — `bug-pascal-statement-call-result-selector`
(`.`) and `bug-a-assignment-through-a-pointer-returned-by-a-function-call-is-dropped`
(`^`/`[`) — and both were one branch that only knew some of the selector tokens.
Check `[` and `.attr` here too, not just `.method()`.

## Gate

`make test-nilpy` + self-host byte-identical, with a `.npy` case covering
`g(3).m()`, `g(3).attr`, `g(3)[0]` and the class-value spelling `cls(3).m()`,
diffed against CPython.
