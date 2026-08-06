---
track: N
prio: 45
type: bug
summary: "NilPy: a closure created in a loop captures the loop variable's VALUE at creation, so [f() for f in fs] gives [0, 1, 2] where CPython gives [2, 2, 2] — Python closes over the variable, not the value"
---

# A closure over a loop variable captures by value, not by variable

- **Type:** bug (semantic divergence) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`. Pre-existing
  (identical on `pinned`).

## Measured (self-hosted at `54fbd2754`)

```python
fs = []
for i in range(3):
    fs.append(lambda: i)
print([f() for f in fs])
# CPython [2, 2, 2]
# pxx     [0, 1, 2]
```

## The awkward part: pxx's answer is the one people usually WANT

This is Python's most notorious gotcha. A closure captures the *variable*, so
every lambda above sees `i` after the loop has finished — all three return 2.
The idiom for the other behaviour is the default-argument trick:

```python
gs = []
for i in range(3):
    gs.append(lambda x=i: x)      # CPython [0, 1, 2]
```

which NilPy currently rejects for an unrelated reason (a lambda default must be
a plain name — see
[[feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep]]).

So pxx today gives the "expected" answer to the surprising form, and cannot
spell the form that legitimately asks for it. That is a bad combination: code
written by someone who KNOWS the gotcha (and is relying on late binding — a real
pattern in callback registration and event handlers) gets a silently different
answer, and the escape hatch is unavailable.

`make(i)` — a factory function, the other standard workaround — is already
correct (`[make(i) for i in range(3)]` gives `[0, 2, 4]`), because each call has
its own frame.

## Why this is filed rather than fixed

Matching CPython means closures share a cell with the enclosing binding, which is
the same machinery
[[bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse]] needs
(a heap cell per captured name, outliving the frame). Doing this one first, on
its own, would mean building that machinery twice. **Take that ticket first** —
it is a hard crash and rated 65 — and this one likely falls out of the same cell
representation.

There is also a question worth a moment before implementing: making every
loop-created closure late-binding will change the behaviour of any existing
NilPy code relying on today's by-value capture. There is no such corpus to
speak of yet, which is an argument for doing it NOW rather than later.

## Gate

Per-fix loop. A `.npy` test covering: the loop-lambda case, the factory-function
workaround (must stay correct), the default-argument idiom once it parses, and a
closure over a variable rebound AFTER the closure is created — all diffed
against CPython with `tools/pydiff.py`.
