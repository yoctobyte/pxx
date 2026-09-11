---
slug: bug-p-a-units-interface-constants-are-invisible-to-a-second-units-implementation-uses
title: "globals' interface constants are invisible inside comphook's implementation -- and it IS the unit-cycle bug, in a shape its fixture could not reach"
track: P
prio: 60
type: bug
status: done
owner: ""
found-by: frankH
created: 2026-09-11
tags: [units, uses, scope, fpc-corpus, consts]
blocked-by: []
summary: "FIXED 2026-09-11. THIS TICKET'S OWN TITLE WAS WRONG: it IS bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface, in an ORDER-DEPENDENT shape that ticket's fixture structurally could not reach. CycleWaitUnit is a GLOBAL and ParseUnitImplSection re-enters itself, so loading a unit named AFTER the cycle-closing one in the same clause cleared the pending park on its way past. comphook's implementation reads `uses cutils, systems, globals, comptty` -- `globals` closes the cycle, `comptty` clears it one name later. THE FOUR REDUCTIONS RECORDED BELOW ALL PUT THE CYCLE-CLOSER LAST, which is exactly why none of them reproduced; the A/B is one token, `uses a, t` fails and `uses t, a` compiles from the same four units, and fpc runs both. globals/rgobj/aasmbase/comphook/cfileutl now all reach `unknown type: TDoubleRec` (feature-b-rtl-has-no-tdoublerec). Fixed by save/restore; new row test_p_a_unit_after_the_cycle_closer_in_one_clause, proven to fail before the fix while the existing ucycle row still passed."
---

# What is measured

```
$ pascal26 -Mobjfpc --mimic-fpc-compiler <corpus flags>   { program d; uses globals; }
pascal26:251: error: undefined variable (V_Status)
  in: /home/neo/src/fpc-trunk/compiler/comphook.pas
  near: ( status . verbosity and V_Status >>> ) <> 0
...20 errors, every one `undefined variable`, every one in comphook.pas
```

Each missing name is a plain constant in globals' interface — `globals.pas:136-152`,
an unconditional `Const` block with no directives in it. `comphook.pas`'s
implementation section reads `uses cutils, systems, globals, comptty;`.

Neighbours, same flags, same binary: `globtype`, `cutils` and `systems`
compile **clean**. `comphook` entered directly stops EARLIER, at
`unknown type: TDoubleRec` (cpuinfo.pas:36) — and entered through `globals`
that error never fires at all, so the V_* failures are **not** a cascade from
it. `grep -c TDoubleRec` over the whole globals run: 0.

# It is NOT the unit-cycle bug, and four reductions do not reproduce it

All four compile under pxx and print exactly what fpc prints:

1. **The plain cycle.** `unit ua` interface-uses `ub`; `ub`'s implementation
   uses `ua` and reads a const from ua's interface. Both: 8192.
2. **Three units**, matching globals/cfileutl/comphook: entry declares the
   const, interface-uses the middle, middle's implementation uses hook + entry,
   hook's implementation uses entry. Both: 16384.
3. **The declarations that precede the const block** — an initialised
   `var localvartrashing: longint = -1;` in an INTERFACE, then a typed-const
   `array[0..nroftrashvalues-1] of int64` whose initialiser includes
   `$AAAAAAAAAAAAAAAA` (which does not fit int64). Both: 8192.
4. The same typed const in a **program**: both print
   `6148914691236517205 8192`.

So the trigger is none of: the cycle itself, the three-level shape, an
initialised interface var, an out-of-range int64 in a typed-const array, or
an error cascade. **Recording the non-reproducing shapes because they are the
expensive part to rediscover** — the next person should start somewhere else.

# How it was mis-attributed, so the next reader does not repeat it

`V_Status` is declared in the corpus and invisible across an
`implementation uses`, which is a sentence-level match for the unit-cycle
ticket's title. I matched the slug to the symptom and wrote it into two commit
messages without opening the ticket — which would have shown `status: done`
in its first ten lines. CLAUDE.md's own note says a stale-park hit matches
SLUGS, not questions; this is the same failure by hand. The check that settles
it costs one command: `git merge-base --is-ancestor <fix sha> origin/master`,
then run the minimal shape.

# Why it matters

It is the first failure of rgobj and aasmbase after
[[feature-b-rtl-has-no-termio-unit-and-no-isatty]] landed, and it is what
[[feature-b-rtl-has-no-tdoublerec]] sits behind — cfileutl's implementation
uses `Comphook, Globals`.


# RESOLVED 2026-09-11 — it was the unit-cycle bug after all

**What this ticket got wrong, and it is the interesting half.** The body below
argues at length that this is NOT
`bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface`,
and backs it with four reductions that do not reproduce. The reasoning was
sound and the conclusion was false. That ticket's fix is real and its fixture
is correct; what neither covered is a clause that names **another unit after
the cycle-closing one**.

`CycleWaitUnit` is a global, and `ParseUnitImplSection` re-enters itself: a
`uses` clause loads each named unit in turn, and loading one runs that unit's
implementation section through the same routine, whose `tkUses` arm opens with
`CycleWaitUnit := -1`. So the wait that `globals` had just set was cleared by
`comptty`, one name later, and the park never fired.

**Why four reductions missed it — the shape, not the effort.** All four put the
cycle-closing unit LAST in its clause, so nothing followed it to do the
clearing. So did the fixed ticket's own `ucycle_b` (`uses ucycle_a;`). The
discriminator is one token:

| `ucyctail_b`'s implementation clause | pxx before the fix | fpc 3.2.2 |
| --- | --- | --- |
| `uses ucyctail_a, ucyctail_t;` | `undefined variable (TAILCONST)` | runs |
| `uses ucyctail_t, ucyctail_a;` | compiles and runs | runs |

**How it was actually found**, since "read the code harder" was not it: a probe
at the park site, printing `CycleWaitUnit` for every implementation `uses`
clause. It printed `CYCSITE unit=comphook cycleWait=-1` directly after
`CYCSITE unit=comptty`, which named the mechanism and the culprit in one line.
Two hypotheses died on their controls before that — a `lib/rtl` name collision
(no `lib/rtl` unit shares a name with the corpus) and the park-table ceiling
that `6e8a821db`'s own commit message names as the silent-degrade path
(`MAX_DEFERRED_IMPLS` 512 -> 8192 changed nothing).

**The mis-attribution section below still stands and is now doubly earned.** I
first blamed this on the cycle ticket without opening it, corrected that to
"not the cycle bug" after measuring the 2-unit shape, and the correction was
also wrong — the second measurement was right about the shape it ran and I
generalised it to the bug. The quantifier was the invention, again.

**What moved:** `globals`, `rgobj`, `aasmbase`, `comphook` and `cfileutl` all
stopped here and all five now reach `unknown type: TDoubleRec`
(`cpuinfo.pas:36`) — [[feature-b-rtl-has-no-tdoublerec]]. Whether any unit
NEWLY COMPILES is a separate claim and is not made here.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
