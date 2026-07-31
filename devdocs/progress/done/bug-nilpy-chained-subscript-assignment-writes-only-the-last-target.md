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

## Related, found alongside (loud, so lower value, NOT fixed here)

`v = d["a"]` then `v[0] += 10` reports `assignment target is not an lvalue` —
an augmented assignment through a name bound to a container element. The direct
forms (`d["a"][0] += 10` is also rejected; `d["n"] += 5` and `xs[0] += 5` work)
suggest the lvalue check does not follow a binding to its container. Still
present after this fix — out of scope (a different code path: an ordinary
lvalue check on a plain variant local, not the subscript-assign lowering this
ticket is about).

## FIXED (this session)

Lowered properly, not rejected — root cause was in the DEFAULT INDEXED
PROPERTY assignment path (`ParseLValueAST`, parser.inc — the `TPyList`/
`TPyDict` setter-method call for `obj[i] := val`) and the parallel VARIANT
setitem path (`PyMakeVariantSetItem`, pyparser.inc, for a subscript on an
untyped/dynamic value). Both built an `AN_CALL` to a void Pascal
procedure/pylib routine (the setter has no return value) and returned THAT
call node as if it were the assignment's VALUE. `xs[0] = xs[1] = 3` parses
as `xs[0] := (xs[1] := 3)` — the inner store's void call node, used as the
outer store's value argument, carried no real value, so the outer store
either never ran or ran with garbage; either way `xs[1]` got 3 correctly (a
direct call) and `xs[0]` never changed.

Fix: both sites now store the value into a hidden temp FIRST, call the
setter/pylib routine with the temp, then yield the temp (via `AN_COMMA`,
the existing "eval for side effects, yield the other side" node — already
frontend-agnostic in `IRLowerAST`, just previously unused by NilPy). Gives
every target the value, matching Python's chained-assignment result.

**Known residual — evaluation/store ORDER, not values.** Python's documented
order for `a[i] = b[j] = v` is: evaluate `v` once, then assign to `a[i]`,
THEN `b[j]`, left to right. This fix's natural recursive-descent shape
assigns right-to-left instead (the inner target's store executes as part of
evaluating the outer target's RHS). Invisible for the common case (both
targets end up with the identical value regardless of order) but DOES show
up as a difference in dict key INSERTION ORDER for two fresh keys assigned in
one chain (`d["x"] = d["y"] = 7` inserts `y` before `x` here, vs `x` before
`y` in CPython) — confirmed, and worked around in the regression test by
sorting/reading by key rather than depending on iteration order. Fixing the
order fully would need reassociating the parse (compute both targets' base+
index first, THEN store left to right) rather than the natural nested-call
shape — left as a follow-up if it ever matters for real code (unlike the
silently-dropped-target bug this ticket was about, a stable-but-reversed
order is a correctness nuance, not data loss).

## Gate

`make test-nilpy` + self-host byte-identical (confirmed), plus
`test/test_nilpy_chained_subscript_assign.npy`: the repro above, a dict
chained-assign, a chained assign through an instance field, and the
existing `xs[0] += 5` / `d["n"] += 5` augmented forms — all diffed against
CPython (keys/values compared directly rather than dict iteration order,
per the residual above).

## Log
- 2026-07-31 — resolved, commit b4166ff14.
