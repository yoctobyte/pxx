---
track: N
prio: 50
type: bug
summary: "NilPy: when two sibling nested defs each have a local of the SAME name, the capture scan records that name as a CAPTURE of each — harmless until a third sibling forward-calls one of them, which then fails with `nested def captures op, which is not in scope at this call`. Renaming one local fixes it."
---

# A nested def's own local is recorded as a capture when a sibling shares the name

- **Type:** bug (ordinary Python rejected) — **Track N**
- **Found:** 2026-08-06, bughunting. Surfaced writing a **recursive-descent
  expression parser** — `factor` / `term` / `expr` as nested defs, the canonical
  shape — which is exactly the code this rejects.
- Compile error, not a wrong value: values stay correct in every shape that does
  compile (checked, see below). That is why it is 50 and not higher.

## Repro (self-hosted at `54fbd2754`)

```python
def outer():
    def fwd():
        return second()      # calls a sibling defined LATER
    def first():
        op = 1               # `op` is a LOCAL here...
        return op
    def second():
        op = 2               # ...and a LOCAL here
        return op + first()
    return fwd()
print(outer())               # CPython 3
```

```
pascal26:3: error: nested def captures op, which is not in scope at this call
```

## The three ingredients, isolated

| variant | verdict |
| --- | --- |
| the program above | **rejected** |
| same, locals renamed `opA` / `opB` | compiles, prints 3 |
| same, but `fwd` defined LAST (so no forward call) | compiles, prints 3 |
| two siblings sharing `op`, no third def calling them | compiles, prints 3 |

So it needs **a forward call to a sibling** AND **that name being a local in
more than one sibling**. A mutual-recursion cycle is NOT required — I chased
that first and it is a red herring.

## Cause — measured with `PXXDBG=n.caps`, not inferred

```
PXXDBG n.caps def outer.fwd    caps=
PXXDBG n.caps def outer.first  caps=op      <- WRONG: op is first's OWN local
PXXDBG n.caps def outer.second caps=op      <- WRONG: op is second's OWN local
PXXDBG n.caps def outer.fwd    caps=op      <- inherited the bogus capture transitively
PXXDBG n.caps MISS op callee=outer.second in=outer.fwd params=
```

The capture scan records `op` — each def's **own local** — as a capture of both
`first` and `second`. `fwd` then picks it up through the transitive-capture rule
(`pyparser.inc`, the "calling a sibling forwards ITS captures" arm, which is
itself correct and was added for songformatter's `redraw`). At the call site the
capture must be resolved in the CALLER's scope, `fwd` has no `op`, and
`parser.inc:13445` reports it.

The contrast proves the misclassification is name-collision-driven: with the
locals renamed, the same probe prints `caps=n` — `n` being `outer`'s parameter,
a genuine capture — and the locals do not appear at all.

## Bounded blast radius (checked)

The bogus capture does **not** corrupt values where the program still compiles.
With an enclosing `op = 100` shadowed by both siblings' own `op`, pxx prints
`103`, matching CPython. So this is a rejection bug, not a silent one — worth
saying explicitly, because a capture list that is wrong looks like it should
produce wrong values and does not.

## Where to look

The scan that fills `PyCapName` / `PyCapCount` for a nested def: a name being
assigned in the def's own body must make it a LOCAL and stop it being considered
a capture, regardless of whether a sibling def also binds that name. Today
something in that resolution sees the sibling's binding. Start from the
`PXXDBG=n.caps` output above — it names the exact def and the exact name, so the
misclassification is observable in one run without a rebuild.

## Gate

Per-fix loop. A `.npy` test with the recursive-descent parser shape (`factor` /
`term` / `expr`, each with a same-named local, forward calls between them),
plus the enclosing-name-shadowing case above to pin that values stay correct,
diffed against CPython with `tools/pydiff.py`.
