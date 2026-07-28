---
track: N
prio: 65
type: bug
---

# Chaining a method call on the RESULT of a method call does not parse

Found 2026-07-28 while testing tuple dict keys
([[bug-nilpy-tuple-dict-key-never-matches]]).

```python
class B:
    def __init__(self):
        self.items = []
    def add(self, x):
        self.items.append(x)
        return self

b = B().add(1).add(2).add(3)
print(len(b.items), b.items)
```

CPython prints `3 [1, 2, 3]`. pxx:

```
pascal26:8: error: expected expression
  near:   add    >>>  add
```

One `.add(1)` on a constructor result is fine; it is the SECOND `.method(...)`
in the chain that stops the parse — the postfix loop does not accept another
call suffix after a call. `return self` builders are ordinary Python and this is
the standard shape for them.

## The silent half

Inside a comprehension the same chain COMPILES and quietly does the wrong thing:

```python
class P:
    def __init__(self, n):
        self.n = n
        self.tags = {}
    def tag(self, k, v):
        self.tags[(k, v)] = self.n
        return self

ps = [P(i).tag("a", i).tag("b", i * 2) for i in range(30)]
print(ps[5].tags[("a", 5)])    # 5      — the first call's store landed
print(ps[5].tags[("b", 10)])   # KeyError — the second call's did not
```

So the two contexts disagree: statement position rejects the chain, expression
position accepts it and drops all but the first call. Whatever fix lands should
make both agree — the comprehension path is the dangerous one, since a builder
that silently applies half its calls looks like it worked.

Related postfix-suffix work: [[project_nilpy_parsefactor_suffix_extension_point]]
records that the suffix hooks live at FOUR routes, which is consistent with one
of them handling a call suffix and another not.

## Gate

`make test-nilpy` plus a `.npy` with a `return self` builder chained three deep,
in BOTH statement and comprehension position, diffed against CPython.
