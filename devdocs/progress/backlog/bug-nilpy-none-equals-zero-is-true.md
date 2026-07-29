---
track: N
prio: 65
type: bug
---

# `0 == None` is True, and `None == 0` does not parse

```python
print(0 == None)      # CPython: False   pxx: True
print(0.0 == None)    # CPython: False   pxx: True
print(False == None)  # CPython: False   pxx: True
print("" == None)     # CPython: False   pxx: False   <- correct
print(None == 0)      # CPython: False   pxx: COMPILE ERROR
```

`None` as a literal on the RIGHT of `==` is compared as the integer 0, so every
falsy number equals None. That is the 0-sentinel showing through
([[project_nilpy_none_routes_sentinels]]): the sentinel is invisible in most
routes, and here it is the answer.

The consequence is the one the sentinel was supposed to avoid: `if x == None`
is True for a legitimate 0, so a real zero reads as "missing".

`None` on the LEFT is a second, separate defect — a PARSE error at statement
level:

```
Expected: ), but got:  (Kind: 64, Line: N)
```

...but the identical expression inside a call (`str(None == 0)`) parses and
returns True. So the asymmetry is in the statement-level expression path only.
Both belong to the same fix: `None` must be a first-class operand of `==`/`!=`
on either side, comparing equal to nothing but None.

Found by the operator × operand-type sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `==`/`!=` between None and
each of 0, 0.0, False, "", [], {} and None, in both operand orders, at
statement level and inside a call.
