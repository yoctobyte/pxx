---
slug: bug-p-a-units-interface-constants-are-invisible-to-a-second-units-implementation-uses
title: "globals' interface constants are invisible inside comphook's implementation, and it is NOT the unit-cycle bug"
track: P
prio: 60
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [units, uses, scope, fpc-corpus, consts]
blocked-by: []
summary: "Compiling FPC's `globals` produces 20 errors, ALL of them `undefined variable` for a constant declared in globals' own interface, ALL of them raised inside `comphook.pas`'s implementation, which does `uses ... Globals`. V_Status/V_Hint/V_Note/V_Warning/V_Error/V_Fatal/V_Parallel and 13 more. IT IS NOT bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface -- that is DONE (d52831ed7 + 6e8a821db, both ancestors of origin/master) and its shape passes: a minimal A/B cycle answers fpc's 8192. I ATTRIBUTED THIS TO THAT TICKET IN TWO COMMIT MESSAGES (d57a1efaa, e1c789fd0) BEFORE CHECKING, AND THAT WAS WRONG. Four reduction attempts do NOT reproduce -- see the body; the shape needs something the corpus has and none of them captured. This is the wall rgobj and aasmbase reached once termio.IsATTY landed."
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
