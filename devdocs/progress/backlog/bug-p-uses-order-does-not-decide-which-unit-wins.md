---
summary: "Two units exporting the same routine: FPC takes the LAST in the uses clause, pxx takes the first. The naive fix (last declaring scope wins in FindProc) was measured to break the NilPy stdlib and the compiler's own self-compile — FindProc's return value is an overload-set REPRESENTATIVE that other code reads types off"
type: bug
track: P
prio: 35
blocked-by: decide-scope-hiding-vs-flat-overload-set
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
