---
track: N
prio: 40
type: bug
---

# NilPy: a single-line `def f(): return x` body fails to parse

- **Type:** bug (NilPy syntax gap — hard error, not a wrong value) — **Track N**
- **Found:** 2026-08-02, incidental, while verifying imported-module scope for
  [[bug-nilpy-identifiers-are-case-insensitive]].

## Measured

`helper.py`:

```python
def get(): return "lower-get"
```

```
pascal26:4: error: unexpected token
Expected: newline, but got:  (Kind: 49, Line: 4)
```

Splitting the body onto its own indented line compiles and runs correctly, so
only the one-line form is affected:

```python
def get():
    return "lower-get"
```

CPython accepts both. The error is reported against the IMPORTING file's line
numbering, not the module's, which is a second small annoyance in the same
report.

## Scope

Only measured for a `def` in an imported `.py` module; not yet checked for a
`def` in the main `.npy`, for a one-line `class C: pass`, or for the other
suite-on-one-line forms Python allows (`if x: return 1`, `while c: n += 1`).
Worth sweeping those together — Python's grammar allows a simple-statement list
after any compound-statement colon, so this is one rule, not four bugs.

## Why it is low priority

Idiomatic Python puts the body on its own line, and the failure is a clean
compile error rather than a wrong value — the expensive class of bug here. It
is filed because it is a *grammar* gap, so it will keep surfacing in
real-world code, not because it blocks anything today.
