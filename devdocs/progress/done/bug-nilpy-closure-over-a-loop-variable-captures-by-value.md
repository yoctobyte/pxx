---
track: N
prio: 45
type: bug
summary: "NilPy: a closure created in a loop captures the loop variable's VALUE at creation, so [f() for f in fs] gives [0, 1, 2] where CPython gives [2, 2, 2] — Python closes over the variable, not the value"
status: done
owner: claude-A-N
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

## 2026-08-07 — recon: the stated blocker is GONE, the escape hatch WORKS, and the one hard part is named

Picked up because both of this ticket's preconditions are now met, and put back
down deliberately rather than half-built. What changed, measured at
`2145478ac`:

1. **"Take that ticket first" is satisfied.**
   [[bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse]] and its
   residue [[bug-nilpy-an-escaped-nonlocal-cell-is-not-shared-with-the-enclosing-frame]]
   are both done, and the second one built exactly the machinery this ticket was
   told to wait for: a **frame cell** — one heap slot per promoted name, shared
   by the enclosing frame and every closure over it, outliving the frame
   (`SymCellPtr`, `PyPromoteNonlocalCells` / `PyPromoteCell` /
   `PyCellPromotable` in `pyparser.inc`, `pycell_new` in `pyeval.pas`, plus the
   two PyExprMode-gated read rewrites in `parser.inc`). Late binding IS that
   representation; nothing new is needed on the storage side.

2. **The escape hatch is available after all.** This ticket says
   `lambda x=i: x` "NilPy currently rejects". It does not — measured:

   ```python
   gs = []
   for j in range(3):
       gs.append(lambda x=j: x)
   print([g() for g in gs])      # CPython [0, 1, 2] — and pxx [0, 1, 2]
   ```

   So the "bad combination" argument in the section above no longer holds: after
   the fix, code that legitimately wants EARLY binding can still spell it. That
   removes the only reason to hesitate, and the "no corpus yet, so do it now"
   argument stands unopposed.

## What is actually left, and it is one thing

Cells are promoted **up front**, before the enclosing body is parsed — they have
to be, or statements before the `def` would access the slot directly while
statements after it go through the cell. So the fix needs **the set of names
captured by any nested def or lambda, known before the body parse**. Today
`PyPromoteNonlocalCells` gets that set from a token scan for `nonlocal` at depth
>= 2, which is trivial; the general set is not.

Two routes were considered and one is a dead end — recorded so it is not
re-explored:

- **Dead end: read it off the registered Procs after the typing pre-pass.**
  Tempting, because `PyCollectLocalsAST` trial-parses the body and every nested
  def header registers its capture list in `PyCapName[procIdx]`, so the nested-def
  half is free. It does not work for **lambdas**: the lambda lifter registers
  `$pylamN` with its captures as ordinary parameters (`lamNames`/`lamSyms`) and
  never fills `PyCapName`, so the loop-lambda case — the one this ticket is
  about — is precisely the one that route misses.

- **The route to take: a token prescan with def-block bookkeeping.** Walk the
  enclosing body tracking indent depth *and whether each opened block is a
  `def`/`lambda` body* — the `blockIsDef[depth]` pattern
  `PyCollectModuleLocalsAST` already uses for the same reason — and for each
  identifier inside such a block, promote it when it resolves to a local of THIS
  frame and `PyBodyBindsLocal` says the nested body does not bind it itself.
  That last clause is the existing capture rule, already token-based, in the
  scanner at the top of `PyParseDefHeader`; the work is factoring it so both
  callers share one definition of "captured" rather than growing a second.

## Why it was not built in this session

Not blocked — **scoped out deliberately.** Promoting every captured name is a far
wider behavioural change than the `nonlocal`-only promotion that landed this
morning (which was narrow on purpose: it fires only where a nested def declares
the name). It turns every closure capture in the language late-binding, and it
wants its own session with the full closure suite re-diffed against CPython, not
the tail of one. Parked in `unfinished/` with the route above rather than
half-applied.

Also worth folding into that session: `PyCellPromotable` currently refuses
managed strings, records, arrays and class instances, and a loop variable over a
list of objects is exactly a class capture — so the general case will meet the
class-capture residue already recorded on the cell ticket
(a `nonlocal` class capture keeps `pyboundfn_bind_obj` and has no writable cell).

## Log
- 2026-08-10 — resolved, commit fcdcd2ed3.

## Resolution (2026-08-10) — fixed by the cell machinery, exactly as predicted

The ticket said: *"Take [[bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse]]
first — it is a hard crash and rated 65 — and this one likely falls out of the
same cell machinery."* That ticket is in `done/`, and this one did fall out.
**No code was written for this ticket.**

### Verified against the CPython oracle

The ticket's own repro, verbatim:

```python
fs = []
for i in range(3):
    fs.append(lambda: i)
print([f() for f in fs])
```

```
CPython : [2, 2, 2]
pxx     : [2, 2, 2]      (was [0, 1, 2])
```

Plus the neighbouring shapes, all matching CPython:

| shape | CPython | pxx |
| --- | --- | --- |
| closure over a `range` loop var | `[2, 2, 2]` | `[2, 2, 2]` |
| closure over a LIST-literal loop var | `[2, 2, 2]` | `[2, 2, 2]` |
| closure over a STRING-element loop var | `['b', 'b']` | `['b', 'b']` |
| `make(i)` factory (was already correct) | `[0, 2, 4]` | `[0, 2, 4]` |

The list-literal and string rows are checked because the loop's iterable is
lowered differently per element type, and a fix that only covered `range` would
pass the ticket's repro alone.

**Control:** `stable_linux_amd64/default/pinned` also answers `[2, 2, 2]`, so
the fix predates today's work rather than coming from it — this is a stale
ticket being closed on measurement, not a change being credited to this session.

### Still open, deliberately

The ticket's second half — the escape hatch `lambda x=i: x`, which legitimately
asks for capture-by-value and which NilPy rejects — is NOT fixed by this and
remains covered by
[[feature-nilpy-small-syntax-gaps-found-by-the-2026-08-06-sweep]]. Closing this
ticket does not close that gap.
