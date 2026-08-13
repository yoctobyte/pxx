---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`mk().items()` where mk() returns a dict built in the body does not parse ('unexpected token'), while binding the result to a local first works. Pre-existing (identical on pinned). Same SHAPE as bug-nilpy-def-returning-a-precreated-global-has-no-return-type, which was fixed for the class case."
status: done
owner: claude-A-N
---

# A selector on a call returning a locally-built dict does not parse

```python
def mk():
    out = {}
    out["a"] = 1
    return out

print(sorted(mk().items()))     # error: unexpected token
```

Binding first works:

```python
d = mk()
print(sorted(d.items()))        # fine
```

- **Found:** 2026-08-13, writing the serializer row for
  [[feature-nilpy-getattr-with-a-computed-attribute-name]] — the shape was
  `to_dict(o, names).items()`.
- **PRE-EXISTING:** identical under `stable_linux_amd64/default/pinned`, so it
  is not from that work.
- **Loud:** a parse error, not a wrong value.

## Why it is probably small

This is the same shape as
[[bug-nilpy-def-returning-a-precreated-global-has-no-return-type]], which was
closed the same day: `<call>.member` failing at PARSE time while the value and
its class are right, and the bind-to-a-local spelling working. That one was a
missing return-TYPE inference for one particular def shape. Here the def
returns a dict it built statement by statement, so the candidate is the same
inference not recognising `out = {}` + `return out` as a TPyDict result.

Check whether the LIST form (`out = []` … `return out`, then `mk().append(1)`)
has the same hole — if it does, the fix is one inference rule and not two.

## Gate

A `.npy` diffed against CPython: a dict and a list built in a def body then
selected on directly, with the bind-to-a-local spelling as the control.

## FIXED 2026-08-13 — and the ticket's own guess was wrong, usefully

The ticket blamed return-type inference, by analogy with its sibling. Measured,
that is not it: `mk().keys()` and `mk().values()` on the very same call already
worked, and so did `mk().get("a")`, `len(mk())` and `mk()["b"]`. Only `items`
failed — and a LITERAL-returning def failed identically, which rules inference
out entirely.

**`items` is the one of the three that COLLIDES.** pylib spells the view
methods `keylist`/`vallist`/`itemlist` precisely to dodge TPyDict's default
`Items[]` property, so on this selector path `items` matched the PROPERTY first
and then died on the `(` with "unexpected token", while the other two names
collide with nothing and sailed through.

So the fix is placement, not inference: the Python-spelling-to-pylib-name remap
(`PyMethNameFor`) now runs where `fieldName` is first read, ahead of the
property and method resolution, instead of beside the method lookup further
down. One site instead of two, and it comes before whatever the collision is
with — which is the only ordering that can be right in general, since the point
of these names is that they collide.

That two thirds of one feature worked is what made this findable: varying the
member NAME across the three views is what located the collision. A repro that
only ever wrote `.items()` would have sent this back to inference.

Test `test/test_nilpy_selector_on_a_dict_returning_call.{npy,expected}`
(`.expected` from CPython), wired into `test-nilpy`: the three views x the
receiver shapes that take this path (call result, subscript), a locally-built
AND a literal-returning def (the inference control), the bind-to-a-local
spelling, the set-update remap through the same site, and a non-colliding dict
method. The 44-file NilPy dict/selector/call family re-run.

Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
