---
summary: "Two units exporting the same routine: FPC takes the LAST in the uses clause, pxx takes the first. The naive fix (last declaring scope wins in FindProc) was measured to break the NilPy stdlib and the compiler's own self-compile — FindProc's return value is an overload-set REPRESENTATIVE that other code reads types off"
type: bug
track: P
prio: 60
status: done
owner: claude-ACPN
---

# `uses a, b` — pxx picks the first unit's routine, FPC picks the last

- **Type:** bug — FPC divergence. Track P.
- **Opened:** 2026-08-05
- **Split from:** [[bug-p-program-function-does-not-shadow-used-unit]], whose
  program-vs-unit half is fixed. That ticket guessed "likely one fix, not two";
  it is two, and this is the harder one.

## Symptom

```pascal
unit shadow_a; ... function Who: AnsiString; begin Who := 'A'; end;
unit shadow_b; ... function Who: AnsiString; begin Who := 'B'; end;

program t; uses shadow_a, shadow_b; begin writeln(Who); end.
```

    FPC : B     (last uses wins)
    pxx : A

and symmetrically `uses shadow_b, shadow_a` gives FPC `A`, pxx `B`... no —
pxx gives `A` there too, i.e. **pxx ignores uses order entirely** and takes
whichever unit registered first.

Two units exporting the same routine is legal Pascal and FPC accepts it
silently, so this is a real divergence, not a diagnostic gap.

## Why the obvious fix is wrong — measured, twice

`FindProc` walks a hash chain that is FIFO = registration order, and used units
register before the compiling scope. The one-line fix is to prefer the last
match. **Do not do this.** It was tried and it broke two unrelated things:

1. **The compiler cannot compile itself.**

       pascal26:18218: error: set item must be one character
         near: EmitAsmX64 >>> sub rsp, 16  movsd [rsp], xmm0

   `EmitAsmX64` has two overloads, `array of const` and `AnsiString`. The
   parser calls `FindProc` and reads the returned proc's **signature** to
   decide whether `[...]` is an open-array constructor or a set. Preferring the
   last entry handed back the `AnsiString` overload, so `[...]` parsed as a set.

2. **The NilPy stdlib segfaults.** `test_nilpy_repr_and_range_consumers.npy`
   dies at `sum(range(i))`. `pyparser.inc` infers expression types by reading
   `Procs[procIdx].RetType` off whatever `FindProc` returns; a different
   scope's entry gave the wrong type and the wrong type reached codegen. Note
   the failure mode — a **runtime segfault far from the cause**, exactly the
   class the debugging playbook is about.

The root of both: **`FindProc` returns a representative of a same-named set,
and callers read types and signatures off it.** It is not a pure "which one
does this call bind to" query, so changing its ranking changes parsing and
inference too.

## What that implies for a real fix

Ranking inside `FindProc` is the wrong layer. Plausible directions:

1. Give the *call-binding* path its own lookup that knows uses-order, and leave
   `FindProc`'s representative selection alone. Most correct, most work.
2. Record a uses-order sequence per unit and rank by it only where a call is
   actually being bound (`MatchProcCall`), never in `FindProc`.
3. Leave it. `uses`-order shadowing between two units is rare next to the
   program-vs-unit case, which is already fixed.

Whoever takes this should assume any `FindProc` ranking change needs the
**limited tier at minimum** — the quick tier passed both broken versions above.

## Gate

`uses a, b` binds b's routine and `uses b, a` binds a's, matching FPC; the
NilPy suite and self-host both stay green. Test material to restore:
`test_shadow_last_uses_wins.pas` with `shadow_a.pas` / `shadow_b.pas` (removed
when this half was split out; the program-vs-unit test remains as
`test/test_shadow_program_over_unit.pas`).


## 2026-08-06 — this is one facet of a single rule, not its own problem

Reframed with the user. `uses a, b` taking the first unit is not a separate
defect from "a program's routine does not shadow a used unit's" — both are the
same missing rule:

> A declaration **hides** a same-named one from an outer or earlier scope,
> unless marked `overload`.

pxx behaves as if everything were `overload` — one flat set across scopes, with
registration order as the tiebreak. Under the hiding rule, the second `uses`
declares into a later scope, so it hides the first, and this ticket's symptom
disappears without a uses-order-specific mechanism.

So **do not fix this in isolation.** A bespoke uses-order ranking would be a
third mechanism sitting next to the two that already exist (name mangling for
nested routines, current-scope preference for exact matches), and it would be
invisible to anyone reading either FPC's rule or ours.

Now blocked on [[decide-scope-hiding-vs-flat-overload-set]], which also carries
the measured reason the one-line "prefer the last chain entry" fix is wrong —
`FindProc` returns an overload-set representative that the parser reads
signatures off and NilPy reads return types off, so ranking there breaks the
self-compile and the NilPy stdlib. Hiding is candidate *removal*, which is a
different and probably safer change.

The repro and test material in this ticket stay valid and are what the decision
should be gated against.


## 2026-08-06 — UNBLOCKED and promoted: this is now the implementation ticket

[[decide-scope-hiding-vs-flat-overload-set]] is decided: **hiding becomes the
default, everywhere** — no flag, no `{$mode}` gate. So this ticket stops being
"uses-order" and becomes the single implementation of the rule, covering both
remaining facets:

- `uses a, b` binds b's routine, `uses b, a` binds a's (this ticket's original
  symptom);
- `IntToStr(5)` reaches the program's `Int64` declaration rather than sysutils'
  equally-convertible one (the convertible-argument case split out of
  [[bug-p-program-function-does-not-shadow-used-unit]]).

One rule fixes both. Prio raised 35 -> 60 to match the decision.

### Build it as candidate REMOVAL, not ranking

This is the part that has already gone wrong once. Do not rank entries inside
`FindProc`'s chain — build the candidate set with hidden declarations excluded,
then resolve normally. Ranking broke the self-compile and the NilPy stdlib
(details above), and both survived `gate.sh quick`.

Same-scope declarations do not hide each other — they are overloads. That is
what keeps `EmitAsmX64`'s `array of const` / `AnsiString` pair working.

### Measure NilPy before believing any estimate

`pyparser.inc` infers expression types from `Procs[procIdx].RetType` off
whatever `FindProc` returns, and hiding can change which procs are candidates
across `pylib` / `pyeval` / `builtin`. That is exactly where `sum(range(i))`
segfaulted. **`--tier limited` minimum.**

## 2026-08-06 — INVESTIGATION (no code changed): the insertion point and the rank source

Spent a session reading rather than editing, because this ticket has already
broken the self-compile and the NilPy stdlib once and the expensive part is
knowing *where* the removal goes. Three findings, all read off the source.

### 1. `MatchElig` is the candidate-removal hook, and it already does this once

`compiler/symtab.inc`'s

```pascal
function MatchElig(idx: Integer; const name: AnsiString; demote: Boolean;
                   bIdx: Integer; userOnly: Boolean): Boolean;
```

is the shared eligibility predicate — **9 call sites, one per matching phase**
(exact, compatible, lifting, …). Adding the hiding test there removes hidden
declarations from the candidate set in *every* phase at once, which is exactly
what the decision demands, and it never touches `FindProc`'s representative. That
is the whole reason ranking failed before: `FindProc` is a different query.

Better still, **the shape is already implemented next door.** `userOnly` /
`PyUserShadowsProc` is name-level candidate removal for NilPy: a module-level
`def sorted(x)` REPLACES pylib's, decided by NAME rather than argument fit,
"and it demotes ALL of the unit's overloads together". Pascal scope hiding is the
same rule with a scope rank in place of "declared by the main program". So this is
not a new mechanism — it is a third instance of one that exists twice
(`demote` for builtin-vs-unit, `userOnly` for NilPy).

### 2. The uses-order rank exists: `CompiledUnits[]`

`CompiledUnits : array[0..255] of Integer` / `CompiledUnitCount` (defs.inc ~1857)
records unit indices **in compile order**, and for a `uses a, b` clause that IS
the uses order — `a` is compiled before `b`. So the rank the ticket assumed had
to be invented is already recorded:

- compiling scope (`ProcUnitIdx = CurrentUnitIdx`) → highest;
- otherwise position in `CompiledUnits` → later = higher;
- builtin unit → lowest.

Note the main program is `ProcUnitIdx = -1` and `CurrentUnitIdx = -1` while not
parsing an imported unit, so the "current scope" arm already falls out of the
existing comparison `ProcUnitIdx[i] = CurrentUnitIdx` used by `FindProc` and
Phase 1 of `MatchProcCall`.

### 3. What the implementation has to get right

- **Compute the winning rank per NAME, once**, then reject lower-ranked
  candidates in `MatchElig`. Do NOT rank inside a phase's loop — that is ranking
  again, and same-scope overloads must all survive together.
- **`overload` is the exemption.** A declaration marked `overload` joins rather
  than hides; that is what keeps `EmitAsmX64`'s `array of const` / `AnsiString`
  pair alive, and same-scope declarations never hide each other anyway.
- **Empty-set guard.** If removal empties the candidate set the call should fail
  as "no overload matches", not silently fall through to a lower scope — but check
  that against FPC before choosing, since a hidden-but-only-candidate case is
  precisely where a wrong choice becomes a new silent divergence.

### Not started, deliberately

The change itself is high-blast-radius (it re-decides binding across `lib/rtl`,
`pylib`, `pyeval` and `builtin`) and the decision requires `--tier limited` as the
minimum evidence, so each iteration is a ~10-minute measurement. Starting it
without room to finish would leave a half-applied Track A change in the tree,
which `tools/progress.sh check` treats as critical — worse than not starting.

Left in the backlog with the ground above under it. A session that picks this up
starts at "add the rank + wire it into MatchElig", not at "where does this go".

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10) — hiding as candidate REMOVAL, both facets

Built exactly as the 2026-08-06 investigation specified: **candidate removal in
`MatchElig`, never ranking in `FindProc`.**

- `ProcScopeRank` — compiling scope > position in `CompiledUnits` (which for a
  `uses a, b` clause IS the uses order) > builtin. The rank did not have to be
  invented; `CompiledUnits` already recorded it.
- `ProcHideRank` — the winning rank per NAME, memoised (MatchElig runs over the
  whole proc table for one name, so recomputing per candidate would make
  matching quadratic). `overload` anywhere at the winning rank returns "no
  hiding", which is what keeps `EmitAsmX64`'s `array of const` / `AnsiString`
  pair alive across scopes.
- `MatchEligBase` — the non-hiding tests, split out so the rank pass and the
  final predicate cannot drift apart.

### Two things the plan did not anticipate

**1. The two call shapes bind through DIFFERENT code.** Fixing `MatchElig` alone
left `WhoP(1)` answering `B` while a bare `Who` still answered `A` — a
parameterless reference binds straight off `FindProc`, which the plan
(correctly) forbade touching. It needed its own *binding* query,
`FindProcBound`, that ranks candidates while leaving the representative alone.
Had only the parameterised half been tested, this would have shipped half-fixed.

**2. Hiding must NOT apply to a QUALIFIED call.** `System.Random(i + 1)` started
reaching the used unit's `Random` instead of the builtin, because the unit
outranks it — caught by `test_builtin_name_demote` in `test-core`, *not* by the
quick tier. A qualified call has already named its scope; hiding only answers
"which declaration does a bare name see". Gated on `demote`, which
`MatchProcCall` already receives as `qUnit = -1`, so no new parameter.

### The ticket's premise, corrected

It states pxx "ignores uses order entirely and takes whichever unit registered
first". It does not — it consistently took the **first** unit in the clause
where FPC takes the last. Symmetric and order-sensitive, just inverted. Worth
correcting because "ignores order" points an investigation at registration
order rather than at direction.

### Measured against FPC

| | FPC | pxx now | pinned |
| --- | --- | --- | --- |
| `uses shadow_a, shadow_b` | `B B` | `B B` | `A A` |
| `uses shadow_b, shadow_a` | `A A` | `A A` | `B B` |
| program's `IntToStr` vs sysutils' | `MINE:5` | `MINE:5` | `5` |
| `System.Random` vs unit's `Random` | `sys-ok` | `sys-ok` | `sys-ok` |

Both facets the promotion note named — uses-order AND the convertible-argument
case — are fixed by the one rule, as predicted.

### Test material restored

`test/shadow_a.pas`, `test/shadow_b.pas`, `test/test_shadow_last_uses_wins.pas`
and `test/test_shadow_first_uses_hidden.pas`, wired into the Makefile. Both
clause orders **and** both call shapes, because a rule that always picked one
unit would pass either order alone, and the two shapes bind through different
code.

### Gate

`--tier limited` **GREEN, 1726/1726** — the minimum the ticket demanded, since
the quick tier passed both previously-broken versions. Plus `gate.sh quick`
GREEN, `make test-core` exit 0 (the one that caught the qualified-call
regression), `make test-nilpy` exit 0 (what the previous attempt broke), FPC
seed canary PASS, self-host fixedpoint byte-identical.
