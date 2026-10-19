---
track: N
prio: 65
type: bug
---

# A generator called from code written ABOVE its def crashes or loops wrong

Found 2026-10-19 while writing the slot-early regression test. It's
pre-existing: 12ddb7d995 does the same.

```python
def early():
    return list(gen(2))

def gen(n):          # also: (n, k=SCALE), (n, xs=None)
    i = 0
    while i < n:
        yield i
        i += 1

print(early())       # CPython: [0, 1]
```

pxx crashes with no output (SIGSEGV) for `gen(n)`, `gen(n, k=SCALE)` and
`gen(n, xs=None)`. With `gen(n, k=3)` it prints `[0, 1, ..., 10]`: n is read
wrong. Defining `gen` above `early` works. This looks like the generator call
or for-in desugar lowering against the shell-pass registration rather than the
real one. That was not investigated.
