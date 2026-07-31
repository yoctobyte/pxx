---
summary: "nilpy: at module level, a name first bound inside if/for/with is 'undefined variable' on the RHS of a later top-level assignment"
type: bug
track: N
prio: 55
---

# A module-level name bound inside a block cannot be READ by a later top-level assignment

- **Type:** bug (Nil-Python frontend — **Track N**)
- **Opened:** 2026-07-31 by Track B, probing songformatter's session loader.
  Filed, not fixed: the fix is in the frontend.

## Minimal

```python
if True:
    payload = 3
documents = payload + 1     # pascal26:3: error: undefined variable (payload)
print(documents)
```

Three lines. It is not about `with`, not about `json`, and not about the module
loader — any nested block does it.

## What separates the working case from the broken one

Measured, one variable at a time:

| module-level shape | result |
| --- | --- |
| `if True: payload = 3` then `print(payload)` | **ok** — prints `3` |
| `if True: payload = 3` then `documents = payload + 1` | **error: undefined variable (payload)** |
| `for i in [1]: payload = 3` then `documents = payload + 1` | **error** |
| `with p.open(...) as f: payload = json.load(f)` then `documents = payload.get(...)` | **error** |
| `payload = 0` first, then the same block and assignment | **ok** |
| all of it inside a `def` | **ok** |

So the name IS bound — an expression statement reads it fine. What fails is
reading it on the right-hand side of another top-level ASSIGNMENT. The two
statement forms are evidently resolving against different views of module scope:
the assignment path only sees names already bound at the top level, while the
expression path sees the names bound inside blocks too.

A pre-declaration at top level (`payload = 0`) makes it work, which is the
workaround — and exactly the app-side edit the compile-real-world-code mission
forbids.

## Why it matters

This is the ordinary shape of a Python entry point:

```python
with SESSION_FILE.open("r", encoding="utf-8") as file:
    payload = json.load(file)
documents = payload.get("documents", [])
```

It is how songformatter's `SongFormatter.py` loads its session, and it is what
made a Track B probe of that file fail to compile even though the module itself
compiles (there the code sits inside `def load_session()`, which is the working
case — so the bug hides until someone lifts the same lines to module level).

At least it is LOUD: a compile error, not a wrong value.

## Where to look

The module-level statement path in `compiler/pyparser.inc` — specifically
whatever set of bound names an assignment statement's RHS resolves against,
versus the set an expression statement resolves against. The asymmetry is the
bug; whichever view is the fuller one is presumably the right answer for both.

## Gate

`make test-nilpy` green + self-host byte-identical, plus a `.npy` covering the
table above (each of `if` / `for` / `with`, read from both an expression
statement and an assignment RHS) diffed against CPython.

## Log
- 2026-07-31 — resolved, commit b2e19af2b.
