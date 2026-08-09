---
prio: 50
track: N
type: bug
blocked-by: []
---

# A lambda whose body is a CALL returning a container yields None

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of type conversions.
- **Owner:** —

```python
f = lambda: list("abc")
print(f())              # CPython ['a', 'b', 'c']    pxx None

g = lambda x: sorted(x)
print(g("cab"))         # CPython ['a', 'b', 'c']    pxx None
```

`list("abc")` written as a STATEMENT is correct. Only through a lambda is it
None, and silently.

## Measured boundary

| lambda body | result |
| --- | --- |
| `[1, 2]`, `(1, 2)` — container LITERAL | correct |
| `"s"`, `7`, `len(s)`, `str(1)`, `abs(-1)` — scalar/string | correct |
| `[1] + [2]` — a binop | correct |
| `x[0]`, `x + 1` — on a parameter | correct |
| **`list(s)`, `tuple(s)`, `sorted(s)`** | **None** |
| **`mk()` where a user def returns a list** | **None** |

So it is exactly: the body is an `AN_CALL` whose result is `tyClass`.

## Cause — deliberate, and this is the third case it caught

`PyCompileLambdaBody` refuses to return a `tyClass`/`tyRecord` value at all.
That refusal is not a bug: it exists because `lambda s: log.append(s)` returns
the CAPTURED list itself, and boxing that into `$pyresult` for a caller who
discards it drove the captured object to refcount 0 and freed it under the
enclosing scope (measured previously with `-dPXX_OBJTRACE`: 4 retains / 5
releases). It is the ARC gap
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]].

`PyLambdaResultIsOwnedTemp` carves a hole for the case that is provably safe: an
`AN_IDENT` of a body-local, i.e. a container LITERAL's hoist temp, which owns
its construction ref. That carve-out was added for
`bug-nilpy-a-tuple-returned-from-a-lambda-becomes-a-list`.

A CALL result is the **third** case and is currently on the wrong side of the
line. `list(s)` and `sorted(s)` build a fresh object and own it exactly as a
literal does — they are not aliases of anything — but the predicate excludes
every `AN_CALL` because a METHOD call might return `Self`.

## The two routes

1. **Widen the carve-out to provably-fresh calls.** The distinction that matters
   is fresh-vs-alias, not call-vs-ident. A call to a pylib CONSTRUCTOR
   (`list`/`tuple`/`sorted`/`set`/`dict`/`bytes`…) always builds a new object;
   a method call on a captured receiver may not. That means an allowlist by
   proc, which the current predicate deliberately avoided ("structural, not by
   name") — but it avoided names for a different question (local vs capture),
   so it is not the same trade.
   **A user def returning a list is NOT safe to include**: the def may return a
   captured global, which is the aliasing case again.
2. **Fix the ARC gap** and drop the refusal entirely. The right answer, and the
   bigger one.

## Verify with the instrument, not by reasoning

Whichever route: check with `-dPXX_OBJTRACE` that retains and releases BALANCE
for the widened shape, the way the previous session did (scalar and managed
string balance 2/2; the aliasing case was 4/5). This is a refcount change, so
"the test passes" is not evidence — a double free shows up later and elsewhere.

## Gate
`.npy` diffed against CPython: `lambda: list(s)`, `tuple(s)`, `sorted(s)`, a
lambda taking a parameter, and the shapes that already work (literal, scalar,
binop, index) as controls — plus `lambda s: log.append(s)` on a CAPTURED list
still behaving, with an `-dPXX_OBJTRACE` balance check on it.
