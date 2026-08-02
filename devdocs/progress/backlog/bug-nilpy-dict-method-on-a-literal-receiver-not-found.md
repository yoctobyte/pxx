---
track: N
prio: 35
type: bug
summary: "`{\"a\":1}.items()` fails with 'TPyDict has no method .items()' — the dict-literal receiver is not resolved, though the same call works through a variable or a method result"
---

# `.items()` on a dict LITERAL receiver is not found

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, while adding
  [[bug-nilpy-dict-missing-copy-and-popitem]].

```python
d = {"a": 1}
print(sorted(d.items()))            # ok
print(sorted(d.copy().items()))     # ok  -- a method RESULT works too
print(sorted({"a": 1}.items()))     # error: Nil Python: TPyDict has no method .items()
print(sorted({}.items()))           # same
```

So it is not about the dict being empty, and not about chaining: a **literal**
specifically fails as the receiver, while a variable or a call result succeeds.

## Not all methods — `.items()` is special-cased

This is the part that narrows the search:

```python
print(type({"a": 1}.popitem()).__name__)   # 'tuple'  -- works on the same literal
```

`popitem` resolves fine on a literal receiver; `items` does not. `.items()` has
its own handling in the for-in path (`for k, v in d.items()` is recognised as a
pair-loop form and rewritten to `keylist`/`vallist` rather than going through
ordinary method resolution — see the `itemsDot` handling in `PyParseForIn`).
The likely cause is that the special case matches on the receiver being a
resolvable NAME, and the ordinary method path is never reached for a literal.

Worth checking `.keys()` and `.values()` on a literal at the same time, since
they are handled alongside.

## Impact

Low — `{...}.items()` on a literal is unusual in real code, and it fails loudly.
Filed because it is cheap to fix once the special case is found, and because
"works through a variable, fails as a literal" is exactly the kind of
inconsistency that costs someone an hour when they do hit it.

## Gate

A `.npy` diffed against CPython: `.items()`, `.keys()` and `.values()` on a dict
literal (empty and non-empty), through a variable, and on a method result.
