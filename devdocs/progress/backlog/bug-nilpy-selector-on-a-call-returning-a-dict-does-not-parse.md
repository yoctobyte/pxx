---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`mk().items()` where mk() returns a dict built in the body does not parse ('unexpected token'), while binding the result to a local first works. Pre-existing (identical on pinned). Same SHAPE as bug-nilpy-def-returning-a-precreated-global-has-no-return-type, which was fixed for the class case."
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
