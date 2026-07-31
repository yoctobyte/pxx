---
track: N
prio: 30
type: bug
---

# pyeval prints a Boolean as 1/0 where CPython prints True/False

Inside a lambda (whose body pyeval interprets), `print(flag)` writes `1` / `0`.
Compiled NilPy code prints `True` / `False`, so the SAME expression renders
differently depending on which of the two implementations ran it — the drift
[[feature-nilpy-lambda-compiled-closure]] warns about, in its smallest form.

```python
v = True
cb = lambda *a: print(v)        # pyeval: 1
print(v)                        # compiled: True
```

Fix: pyeval's print/str path must honour the VT_BOOL tag (tag 4) like
`pystr_of` does, not fall through to the integer formatting. Or the whole
question disappears once lambdas compile.

## Gate

`make test-nilpy` with a lambda printing a Boolean, CPython-diffed.

## RESOLVED — verified no longer reproduces (Track sweep, 2026-07-31 @6dc789267)

Tested on a fresh fixedpoint compiler at HEAD (6dc789267):
```
v = True;  cb = lambda *a: print(v);  cb();  print(v)     # -> True / True
w = False; cb2 = lambda *a: print(w); cb2(); print(w)     # -> False / False
```
Matches CPython exactly. The lambda body no longer prints 1/0.

Root cause resolved via the path the ticket itself predicted ("the whole
question disappears once lambdas compile"): lambdas are now LIFTED and compiled
(cab5a5179 lift zero-param lambdas, 4cb96a3b6 name-bound lambda callable,
3d78a527d escaping closure captures), so the lambda body no longer goes through
pyeval's integer-formatting fallback. Fixed as a side effect of the lambda-lift
work, not a targeted pyeval bool-tag patch — either way, gone.

## Log
- 2026-07-31 — resolved, commit 6dc789267.
