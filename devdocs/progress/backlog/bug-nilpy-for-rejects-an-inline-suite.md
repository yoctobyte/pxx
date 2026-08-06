---
track: N
prio: 35
type: bug
summary: "NilPy: `for i in r: body` on one line is a parse error, while `if c: body` and `while c: body` both accept the same inline suite"
---

# `for` rejects an inline suite that `if` and `while` accept

- **Type:** bug (parse inconsistency) — **Track N**
- **Found:** 2026-08-06, bughunting. Loud, not silent — but it rejects ordinary
  Python and the inconsistency with `if`/`while` is the tell that it is an
  oversight rather than a deliberate subset boundary.

## Measured (self-hosted binary at `412fda7a3`)

```python
f = 1
for i in range(1, 5): f *= i     # pascal26:2: error: unexpected token
print(f)                         #   Expected: newline, but got: f (Kind: 1, Line: 2)
```

The same body indented on the next line compiles and prints `24`. The other two
compound statements accept the inline form today:

```python
x = 1
if True: x += 5        # OK, prints 6
while x < 5: x += 1    # OK, prints 5
```

The body form is irrelevant — `for i in range(1, 5): f = f * i` fails the same
way, so it is the inline suite after `for`, not the augmented assignment.

## Why it is worth fixing rather than documenting

One-liner `for` is common in real Python, and this shape also *masks other
bugs*: the case that surfaced it was a factorial loop written to probe
arbitrary-precision arithmetic, and the parse error hid the actual (wrong-value)
result until the loop was re-indented — see
[[bug-nilpy-augmented-assignment-truncates-to-32-bits]].

Note [[bug-nilpy-one-line-class-body-restraint-is-no-longer-enforced]] is the
neighbouring one-line-suite ticket; whoever takes either should read both, since
the suite parser is shared ground.

## Gate

Per-fix loop. A `.npy` test with inline `for`, `if` and `while` suites (and a
`for … else`) diffed against CPython.
