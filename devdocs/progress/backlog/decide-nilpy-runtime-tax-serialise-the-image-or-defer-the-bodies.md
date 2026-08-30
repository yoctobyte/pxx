---
track: U
prio: 60
type: decide
blocked-by: []
summary: "The NilPy fixed tax (~2.2s/compile, ~1,940 CPU-s per full tier) has two possible routes and the ticket assumes one. Serialising the compiled unit image is a 176+ parallel-array checklist that every future Track A commit can silently invalidate. Deferring routine bodies persists nothing and has no staleness class, but only pays if most bodies are unreachable, which is unmeasured. Decide the route before either is built."
---

# Serialise the compiled unit image, or defer the bodies?

- **Type:** decide (Track U). Raised 2026-08-30 by frankA while surveying
  [[perf-a-cache-the-compiled-nilpy-runtime-unit-image]] [A p60] **before**
  writing code, because the survey changed the risk enough to be worth a
  decision rather than a guess.
- **Nothing is blocked on this today** — it decides which of two projects gets
  built, and both are large enough that starting the wrong one is the expensive
  mistake.

## The cost being attacked

Measured at HEAD `eb3b0fd5c642`, loadavg 2.76:

| | |
| --- | --- |
| zero-byte `.npy` | 2.39 / 2.51 / 2.42 s |
| `begin end.` (Pascal) | 0.21 s |
| **fixed NilPy tax** | **~2.2 s per compile** |

Every `.npy` compile parses `pylib.pas` (18,768 lines) + `pyeval.pas` (5,692)
before looking at the user's program, from an unguarded injection at
`pyparser.inc:34707-34708`. At 719 NilPy jobs per full tier that is roughly
**1,600 CPU-seconds a tier**, plus the same 2.2s on every NilPy user's
hello-world.

## Option A — serialise the compiled unit image (what the ticket assumes)

Persist the compiled result and load-and-relocate instead of re-parsing.

**Cost, counted rather than estimated.** The design names "`Code[]`, `Procs`,
`Syms`, `UCls`, the fixup and RTTI tables" — five things. They are not five. The
capacity growers resize **100** proc-indexed arrays, **44** sym-indexed and
**32** field-indexed: **176 parallel arrays**, before `Code[]`, the string pool,
RTTI and fixups. `defs.inc` declares **242** `array of` globals.

**The standing hazard.** Every one must be serialised, and every array added by
any future Track A commit must be added to the serialiser or the cache silently
emits stale code. This repo has a **named failure class** for precisely this —
`symtab.inc:3932`, *"the 'one of six parallel arrays not written' class this
file's SymTR comment names"* — with a measured instance: twelve symbols carried
an immediate pointee over depth 0 because only nine of twenty-one write sites
touched the whole tuple. A unit-image serialiser makes that class permanent and
puts it at the widest blast radius in the compiler: not a wrong value in one
program, but a compiler that compiled something else.

**What would make it acceptable.** Not review, and not the single-program
`same key => same bytes` check the ticket currently implies — that passes a
serialiser which forgot 170 of the 176. It needs **cold-vs-cached byte-identity
over a corpus**, because a missed array is observable only if some program's
output depends on it. Track T's **719 NilPy jobs** are that corpus and are the
only coverage instrument I would trust here.

**Upside:** helps unconditionally, whatever the user's program uses.

## Option B — defer routine bodies, parse only what is reached

Do not persist anything. Record each routine body's token range at parse time and
parse a body only when something reaches it.

**Why it is idiomatic here and not speculative:** the generic path already has
the primitive. `GenericMethodBodyEnd` computes a body's token extent and
`AppendTokenRangeToTemplateArena` buffers it for later parsing
(`pasparser_generic.inc`). What does not exist is any body-skipping in the normal
unit path (grepped; no hits) — so this is new work, but not a new idea.

**Upside:** persists nothing, so it has **no staleness class and no 176-entry
checklist**, ever. It also helps every large unit, not only NilPy — the same tax
is paid by `uses pylib` from plain Pascal (2.1s measured previously).

**Risk / unknown:** it only pays if most bodies are unreachable, and **that is
unmeasured**. It also does not help the parse of interface sections, which is
part of the 24,460 lines. If a typical `.npy` reaches most of `pylib`, this buys
little.

## The decision, and the cheap thing that informs it

**Recommendation: measure B's ceiling before committing to A.** One number
decides it — the fraction of `pylib`+`pyeval` routine bodies actually reached by
a representative `.npy`. `--dce-report` already exists and DCE already drops
unreachable routines *after* they are parsed, so the reachable-body count is
obtainable today without building anything.

- If most bodies are unreachable, **B** is the better project: comparable win,
  no permanent staleness class, wider benefit.
- If most are reached, **B**'s ceiling is low and **A** is the only route — and
  then A must land with the corpus-wide cold-vs-warm gate from the start, not as
  a follow-up.

Doing that measurement is small and is worth doing whichever way this goes. What
should **not** happen is 176 arrays of serialiser being written on the assumption
that A is the only option, which is what the parent ticket's wording invites.

## MEASURED, same session — B's ceiling is real, not marginal

`--dce-report` is **off for the NilPy frontend** (*"only the Pascal frontend is
wired up so far"*), so this went through the Pascal path, which pays the same tax
via an explicit `uses`:

| program | bodies | live | dead | dead by count | dead by emitted size |
| --- | ---: | ---: | ---: | ---: | ---: |
| `uses pylib` | 1261 | 382 | 878 | **69.6%** | 66.2% |
| `uses pylib, pyeval` (what a `.npy` injects) | 1654 | 653 | 998 | **60.3%** | 40.4% |

**About 60% of the injected runtime's routine bodies are never reached** in the
full configuration. That is B's ceiling and it is substantial.

**Three honest qualifications, because the number is more attractive than it is
precise:**

1. **Count is not time.** Live bodies are *larger* on average — 653 live bodies
   carry 749,377 B against 998 dead ones at 509,775 B — so dead is 60% by count
   but only 40% by emitted size. Parse cost tracks *source* size, which I did not
   measure per body, so 60% is an upper bound on bodies skipped, **not** a
   predicted 60% time saving.
2. **This is a program that does nothing.** A real `.npy` reaches more. The
   figure is the ceiling for the best case, not the typical case.
3. **It does not touch interface parsing**, which is part of the 24,460 lines and
   which B cannot avoid.

**So the recommendation firms up to B-first**: a route with no staleness class
and a ~60%-of-bodies ceiling is worth prototyping before committing to a
176-array serialiser that must be maintained forever. If a prototype shows the
real saving is small — because interfaces dominate, or because typical programs
reach most bodies — that is a cheap negative, and A is still there.

Still a **decision**, not a conclusion: A is unconditional and B is not, and
choosing to bank a permanent maintenance hazard for an unconditional win is
exactly the sort of trade that should be made deliberately by the owner.
