---
track: N
prio: 35
type: bug
---

# NilPy: def returning both a str and an int literal SIGSEGVs on the int arm

```python
def g(cond):
    if cond > 0:
        return "pos"
    return 42
g(1)    # fine
g(-1)   # SIGSEGV
```

Return-type inference takes the first typed return ("pos" → AnsiString
Result); the `return 42` arm then stores the INT 42 as a string handle and
the consumer dereferences it. CPython returns int 42. Pre-existing
(reproduces on the pinned compiler); found 2026-07-22 while testing the
variant call-result boxing fix. Correct shape: a def whose returns mix
str and non-str should infer a VARIANT result (same widening the
trial-typing already does for locals: tyString+tyAnsiString widen — extend
the mix rule across classes). Crash, not silent — but a natural Python
idiom, so worth p35.

Repro: probe above; gate = pxx output matches CPython (`pos` / `42`),
test-nilpy green.

## Log
- 2026-07-22 — resolved, commit 3f8f7786.
