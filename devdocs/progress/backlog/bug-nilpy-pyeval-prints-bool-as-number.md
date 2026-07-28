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
