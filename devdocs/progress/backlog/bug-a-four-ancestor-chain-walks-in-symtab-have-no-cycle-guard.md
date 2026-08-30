---
track: A
prio: 45
type: bug
status: backlog
found: 2026-08-30
found-by: frankD
blocked-by: []
summary: "EIGHT unguarded chain walks in symtab.inc across TWO chain structures -- and one is live, not latent: FindSym is where the urgent two-definitions hang spins. Four walk curr := UClsParent[curr] with no cycle guard -- FindUField:1225, FindUMeth:1275, IsSubclassOf:1308, FindUProp:1366. A parent cycle spins in any of them forever, silently, with flat RSS: no OOM, no crash, no output, no exit status. The 2026-08-15 fix for bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler put its guard on the DECLARATION path in pyparser.inc, closing one route to a cycle and leaving every walk that a second route would hang in. Latent -- no current repro reaches it."
---

# Four ancestor-chain walks in `symtab.inc` have no cycle guard

- **Type:** bug (latent non-termination) — **Track A**, `symtab.inc` is shared ground.
- **Found:** 2026-08-30 by frankD while diagnosing
  `bug-n-a-class-with-two-definitions-of-one-method-hangs-the-compiler-forever`.
  **Not that bug** — see "Why this is filed separately".
- **Filed, not fixed:** frankD holds Track D only. `symtab.inc` is also the file
  frankA named as its *next* ticket, so this wants coordinating, not grabbing.

## The code — and it is four places, not one

| function | line |
| --- | --- |
| `FindUField` | `symtab.inc:1225` |
| `FindUMeth` | `symtab.inc:1275` |
| `IsSubclassOf` | `symtab.inc:1308` |
| `FindUProp` | `symtab.inc:1366` |

Each is the same shape:

```pascal
  curr := ci;
  while curr >= 0 do
  begin
    ... look for the name in curr's own rows ...
    curr := UClsParent[curr];      { no visited set, no depth bound }
  end;
```

If `UClsParent` ever contains a cycle — `UClsParent[c] = c`, or any longer ring —
none of these terminates. They allocate nothing and call nothing instrumented, so
the process sits at 100% CPU with **flat RSS**: no OOM, no crash, no output, no
exit status. **A hang is the one failure that does not report**, and this is its
silent variety.

I went looking for one and found four, which is the actual finding. A guard added
to whichever function a future repro happens to land in would leave three.

## Why the existing guard does not cover this

`bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler` (resolved
2026-08-15, `5fd842e6a`) **was this hang**. Its write-up: the NilPy class and its
base became one row, `UClsParent[ci] := ci`, *"and the ancestor walk spun."*

Its three changes all sit **upstream of the walks**:

1. `parser.inc` — a forward stub is filled only by its own unit (the real fix,
   closing the route by which two classes merged into one row);
2. `pyparser.inc` — a qualified base resolves in the named module;
3. `pyparser.inc` — a **declaration-time** guard: `baseCi = ci` or
   `PyClsHasAncestor(baseCi, ci)` reports *"class X cannot inherit from itself"*.

Change 3 is the cycle guard, and it guards the **NilPy class-declaration path**.
The walks are untouched. So that ticket closed the one known route to a cycle and
left the loops that turn any *other* route into the same silent hang — including
routes through the Pascal frontend, which never passes through change 3 at all.

**A guard on the producer protects the cases you thought of; a guard on the
consumer protects the ones you did not.** This asks for the second *in addition
to* the first, not instead of it.

## Why this is filed separately from the ticket that found it

The `two-definitions` hang has **no inheritance in its repro** (`class C:`, bare),
and its third required ingredient — a later scope holding a local of the same name
— would be irrelevant to a parent cycle, which hangs on any attribute lookup
regardless of what comes later. The ingredient set argues *against* these being
one defect, and folding them together would be exactly the duplicate-by-symptom
that the same diagnosis pass ruled out for `[N p68]` by measurement.

Filed at prio 45 for the honest reason that **no current repro reaches it**. It is
a guard against the recurrence of a hang that has already happened once.

## Fix shape

A depth bound or a seen-set on the `curr` walk, reporting a diagnostic instead of
spinning — in **all four**, in one pass. Fixing one arm of a multi-arm case and
leaving the rest is the failure `devdocs/dev/normalise-dont-special-case.md` is
about, and here the arms are already enumerated above so there is no excuse for
finding them one hang at a time.

Worth considering instead of four guards: a single `UClsParentSafe(curr)` (or a
one-time validation of `UClsParent` when a class is finalised) so the invariant
lives in one place. Four copies of a guard is four places for the fifth walker to
not be added — and `PyClsHasAncestor` in `pyparser.inc` is arguably the fifth
already.

## Gate
`make compiler/pascal26` (which *is* the byte-identical self-host fixedpoint) plus
a repro that builds a cycle deliberately. Track T sweeps the matrix.

---

## Update 2026-08-30 — one of these is not latent, and there are more of them

**`FindSym` is where `bug-n-a-class-with-two-definitions-of-one-method-hangs-the-compiler-forever`
[N, urgent] actually spins** — three gdb `rip` samples, resolved through a map
built from the same source as the sampled binary: `FindSym +1227`, `StrEqual +4`,
`StrEqual +62`. Full method in that ticket.

So this ticket's premise needs amending on both counts.

**It is eight walks, not four, across two different chain structures:**

| chain | function | line |
| --- | --- | --- |
| `UClsParent` (ancestors) | `FindUField` | 1225 |
| | `FindUMeth` | 1275 |
| | `IsSubclassOf` | 1308 |
| | `FindUProp` | 1366 |
| `SymHashPrev` (symbol hash) | `FindSym` (exact-case pass) | 3764 |
| | `FindSym` (case-insensitive fallback) | 3781 |
| | `FindSymInUnit` | 3859 |
| | `FindSymInUnit` | 3870 |

Every one is `while i >= 0 do ... i := <chain>[i]` with no visited set and no
bound. **Two independent chain structures with the same missing guard is not a
coincidence about either chain** — it is the file's convention, and a ninth walk
will be written the same way unless the guard lives somewhere a new walk has to
pass through.

**It is not latent.** This ticket was filed at p45 with the honest note that *"no
current repro reaches it"*. **A repro does** — it is the top item on the board.
The `UClsParent` half may still be latent; the `SymHashPrev` half is being hit
right now.

**Prio left at 45 deliberately**, and this is a routing statement rather than a
severity one: the urgent ticket is the one that should be worked, and it will
land the guard where it is needed. This ticket's remaining value is the *other
seven* walks — the ones that will not be fixed by whatever closes the hang. Raise
it only if the hang gets fixed narrowly.

**Which strengthens the fix shape already argued above.** One
`ChainStepChecked`-style helper (or a validation of each chain when it is built)
beats eight copies of a guard, because eight copies is eight places the ninth
walk will not be added. The hang's own ticket carries the suspected cause —
`SymRollbackTo`'s *"the highest live idx is always its bucket's current head"*,
asserted in a comment and never checked — and that is a **producer** fix. This
ticket is the **consumer** half, and the argument above stands: a guard on the
producer protects the cases you thought of; a guard on the consumer protects the
ones you did not. **Both, not either.**
