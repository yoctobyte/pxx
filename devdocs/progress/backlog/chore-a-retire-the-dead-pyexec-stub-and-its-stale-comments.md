---
track: A
prio: 20
type: chore
summary: "compiler/builtin/pylib.pas still carries a no-op `pyexec` stub, plus comments in pylib.pas and pyeval.pas saying things SEGFAULT 'because pyexec is a stub'. Engine 1 landed 2026-07-31 and `exec` lowers to pyeval's EvalPyStmts — nothing calls the stub. The stale prose is the cost: it reads as an unimplemented feature and made a reader doubt a done, gated one."
---

# Retire the dead `pyexec` stub and the comments that outlived it

- **Track:** A (file-lane — `compiler/builtin/**`, so it needs
  `stabilize-fast && pin` like any builtin change). Low prio: a rider for the
  next builtin change, not worth its own pin.

## What is actually true

`exec(src, g, l)` in a `.npy` is lowered in `compiler/parser.inc:12167` to a
direct call to **`EvalPyStmts`** (`compiler/builtin/pyeval.pas:51`) — the
Engine 1 tree-walker from [[feature-lib-pyexec]], resolved by
`FindProc('EvalPyStmts')` and erroring by name if pyeval is not ambient. It
works, and it is gated from the outside by a test diffing whole output against
CPython (`b089d1759`).

## What the tree says instead

| site | text |
| --- | --- |
| `compiler/builtin/pylib.pas:14161` | `procedure pyexec(...)` — empty body, *"No-op for now so the program links."* |
| `compiler/builtin/pylib.pas:1566` | *"(cache, then a tree-walker) is feature-lib-pyexec, a large separate subsystem"* — written as future work |
| `compiler/builtin/pyeval.pas:9` | *"…that SEGFAULT today because pyexec is a stub"* |

Nothing lowers to `pylib.pyexec`. It is dead code whose comment describes the
state of the world before 2026-07-31.

## Why it is worth a ticket at all

It is not the dead procedure — it is that **three independent comments assert a
shipped, gated feature is unimplemented**, and they are the first thing a grep
for `pyexec` returns. That cost one reader a full measurement pass to
disbelieve, on a day when the same reader was deciding policy on top of it.
Same family as [[feedback_measuring_a_thing_is_not_filing_it]]'s "the file
exists does not imply the work is done", inverted: *the comment says stub, and
the feature is done.*

## The work

1. Delete `pyexec` (interface at `pylib.pas:1568`, body at `:14161`) — after
   confirming nothing outside `compiler/builtin/**` references it.
2. Fix the two stale comments to describe `EvalPyStmts` as the live entry
   point, with the `parser.inc` lowering site named.
3. Gate: `make compiler/pascal26` + `tools/gate.sh quick`; then
   `make stabilize-fast && make pin` because it is a builtin change
   ([[project_builtin_change_needs_repin_for_gate_fixedpoint]]).

If step 1 turns out to be load-bearing after all — a `FindProc('pyexec')`
somewhere — do step 2 alone and say so here; the comments are the whole value.
