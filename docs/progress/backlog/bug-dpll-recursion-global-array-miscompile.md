# DPLL backtracking miscompiles: satisfiable formula reported UNSAT

- **Type:** bug (compiler / codegen) — **Track A**
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-22
- **Relation:** surfaced after fixing
  [[bug-impl-prescan-codegen-regression]] (the name-collision fix). With clause
  counting now correct, the sat solver's *verdict* is still wrong. Blocks
  `feature-sat-solver-library` (Track B), which is otherwise FPC-correct.

## Symptom

The `sat` DPLL solver returns the wrong satisfiability verdict for *satisfiable*
instances. On `examples/sat/satdemo.pas` (post name-collision fix, v34):

```
sat3  : UNSAT (3 vars, 3 clauses)   FAIL: want SAT
chain : UNSAT (3 vars, 3 clauses)   FAIL: want SAT
unsat2: UNSAT (2 vars, 3 clauses)   OK
php32 : UNSAT (6 vars, 9 clauses)   OK
php43 : UNSAT (12 vars, 22 clauses) OK
```

Clause/var counts are now correct; the UNSAT instances are right; the **SAT
instances are wrongly reported UNSAT**. So `DPLL` never finds a satisfying
assignment that exists.

## Isolated FPC-vs-PXX repro (same source, divergent output)

Inlining the unit bodies into one program (`lib/rtl/sat.pas` lines 54–256 under a
`program` with the `gNumVars/gLits/gClauseStart/gAssign` globals + `TIntArray`)
and solving the SAT instance `(x1∨x2)∧(¬x1∨x3)∧(¬x2∨¬x3)`:

| compiler | `sat3` result |
|----------|---------------|
| `fpc -Mobjfpc` | `1` (srSat) — **correct** |
| PXX (v34) | `0` (srUnsat) — **wrong** |

Identical source, divergent codegen → a genuine PXX bug, distinct from the
name-collision one (there is **no** function/local name clash in `DPLL`,
`Solve`, or `ClauseStatus`).

## Suspect surface

`DPLL` (`lib/rtl/sat.pas:181`) is a **paramless recursive function** that mutates
a **module-global dynamic array** `gAssign` and snapshots/restores it via a
**local dynamic array** `pre` across the recursion + backtrack:

```pascal
SetLength(pre, gNumVars + 1);
for i := 0 to gNumVars do pre[i] := gAssign[i];   { save }
...
gAssign[v] := 1;
if DPLL then begin Result := True; Exit; end;     { recurse }
for i := 0 to gNumVars do gAssign[i] := pre[i];   { restore on backtrack }
gAssign[v] := -1;
if DPLL then begin Result := True; Exit; end;
for i := 0 to gNumVars do gAssign[i] := pre[i];
```

Likely-fault areas to bisect (each independently testable):
- a **local dynamic array (`pre`) across self-recursion**: is each recursion
  level's `pre` a distinct buffer, or is the handle/length shared/aliased so a
  deeper call clobbers a shallower frame's snapshot?
- **`Result := True; Exit` unwinding** through several recursion levels (does the
  boolean result propagate correctly up every `if DPLL then ... Exit`?).
- writes to a **global dyn-array element** (`gAssign[v] := val`) interleaved with
  recursion — value/handle reload after the call.

Note the `unit` single-clause instance (`p cnf 1 1`, clause `1`) is *also* wrong
under FPC in the inlined repro → that one is a **Track B algorithm** edge case
(single unit clause), not this codegen bug. Keep the two separate: this ticket is
only the SAT instances that FPC gets right and PXX gets wrong (`sat3`, `chain`).

## Suggested next steps (Track A)

1. Minimize: a paramless recursive function that saves a global dyn-array into a
   local dyn-array, recurses with a mutation, and restores on backtrack; check a
   computed result vs FPC. Scale down from `DPLL`.
2. Bisect the three suspect areas above (local-dynarray-per-frame first — most
   likely given the [[project_cross_managed_aggregates]] / dyn-array handle
   landmines).
3. Add the minimized case to `make test` once fixed.

## Log
- 2026-06-22 — Filed (Track A) after the name-collision fix unblocked clause
  counting but left the solver verdict wrong. Clean FPC-vs-PXX standalone repro
  in hand. Distinct from [[bug-impl-prescan-codegen-regression]].
