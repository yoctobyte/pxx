---
track: N
prio: 50
type: bug
---

# `xs[0] = xs[1] = 3` writes only `xs[1]` — the other target is silently skipped

```python
xs = [0, 0]
xs[0] = xs[1] = 3
print(xs)        # CPython: [3, 3]     pxx: [0, 3]
```

Python assigns the value to EVERY target, left to right. pxx assigns the
rightmost one and drops the rest, with no diagnostic.

## Boundary

| form | pxx |
| --- | --- |
| `a = b = 3` (plain names) | **compile error** — `undefined variable (b)`. Loud, fine. |
| `xs[0] = xs[1] = 3` (subscripts) | **`[0, 3]`** — silent, wrong |
| `a = 5; b = a` | correct |
| `d["n"] += 5`, `xs[0] += 5` | correct |

So the plain-name chained form is rejected loudly and only the SUBSCRIPT form
compiles and then misbehaves. That is the dangerous half: a program using it
gets a half-initialised structure and no signal.

## Shape of a fix

Either lower a chained assignment properly — evaluate the value once, then
store it into each target left to right, which is Python's documented order —
or reject the subscript form the way the plain-name form is already rejected.
Rejecting is a legitimate interim step and strictly better than the current
behaviour, since the language does not otherwise support the construct.

If lowering it properly: Python evaluates the RHS once and the target
subexpressions in order, so `f()[i()] = g()[j()] = v()` calls `v`, then `f`,
`i`, then `g`, `j`. Getting the count of evaluations right matters when the
subexpressions have side effects.

## Related, found alongside (loud, so lower value)

`v = d["a"]` then `v[0] += 10` reports `assignment target is not an lvalue` —
an augmented assignment through a name bound to a container element. The direct
forms (`d["a"][0] += 10` is also rejected; `d["n"] += 5` and `xs[0] += 5` work)
suggest the lvalue check does not follow a binding to its container.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` with the table above
against CPython's own output. If the decision is to reject rather than lower,
the test asserts the compile error instead — but it must not stay silent.
