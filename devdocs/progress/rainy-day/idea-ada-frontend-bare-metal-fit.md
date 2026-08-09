---
track: U
prio: 20
type: idea
summary: "Ada is the least alien frontend on offer — it descends from Pascal, and pxx already has subrange types with {$R+} range checks raising error 201, which is Ada's Constraint_Error semantics with the default inverted. The cheap subset (no allocation, no tasking) is also the subset embedded Ada actually ships"
---

# Ada frontend — why the bare-metal target is the sane one

- **Type:** idea (feasibility note, not a commitment)
- **Track:** U → Track **L** (Legacy) once the lane exists; see below
- **Status:** rainy-day — noted 2026-08-09. Nobody has agreed to build this.
- **Owner:** —
- **Related:** [[idea-cobol-frontend-feasibility-costing]]

## Track letter: L for Legacy (decided 2026-08-09, user)

Ada and COBOL share one lane, **L — Legacy**. Neither can have its initial: A is
compiler core, C is the C frontend. The shared property is real rather than a
convenience: both are ISO-standardised, both are conformance-suite-driven
rather than reference-implementation-driven, and both are still in production
in domains that outlive fashions.

**The CLAUDE.md section is deliberately NOT added yet.** Same rule Track W
followed — a lane is declared when the lane actually starts, because a lane
other agents cannot see does not exist, and a letter with no code behind it is
exactly the inflation the "don't invent letters" bar exists to prevent. When
the first `adaparser.inc` or COBOL equivalent lands, add the section then, and
enumerate the languages in its scope line. Do not leave L's meaning to be
inferred: `meta-track-w-collision-windows-vs-website` is what that costs.

"Historic" (Track H) was considered and rejected — Ada flies current avionics
and COBOL runs current banking; the word would read as wrong to the people who
use them.

## Why Ada is the cheapest frontend on the list

**It descends from Pascal.** Packages map onto units, and subranges,
enumerations, records, arrays and strong static typing are all shapes this
compiler was built around. Of every candidate frontend, Ada asks the backend
for the least that is new.

**The constraint machinery already exists.** Verified against the pinned
compiler:

```pascal
type Angle = 0..359;
var a: Angle; i: Integer;
begin
  i := 400;
  {$R+}
  a := i;        { Runtime error 201 (range check error), exit 201 }
```

That is Ada's `type Angle is range 0 .. 359` raising `Constraint_Error`, with
one difference: pxx makes the check opt-in per region and Ada mandates it.
Inverting a default is not a new subsystem.

## Why bare metal is the *right* first target, not a downgrade

The subset that is cheapest to implement is the same subset embedded Ada
actually deploys:

- **No dynamic allocation.** Already the plan; also how high-integrity Ada is
  written in practice.
- **No tasking.** The expensive part of Ada — rendezvous, protected objects —
  and restricted profiles that omit or heavily constrain it (Ravenscar,
  zero-footprint runtimes) are standard practice on small targets, not a
  compromise invented here.
- **Static layout, checks on, no runtime to speak of.** That is the profile
  pxx's bare-metal ESP32 targets (xtensa, riscv32, both emit-only) already
  impose.

So the honest framing is not "Ada, minus the hard parts". It is the profile the
domain already uses, which is why Ada on an ESP32-class part is a coherent
target rather than an exercise: it is what the language was designed for.

## What is still not free

Generics, exception propagation, representation clauses (bit-level record
layout — though `packed record` is a start), and `'Image`/attribute machinery.
Tasking should be explicitly out of scope in any first pass.

## Corpus

**ACATS**, the Ada Conformity Assessment Test Suite, is the official conformance
suite, and **GNAT** is available as a differential oracle — the same shape as
the CPython oracle that drove Track N, and the same shape as
`tools/c_torture_harvest.sh` (vendored corpus, cross-check against the
reference, never auto-dismiss a candidate because the reference disagrees).
**Licensing and current packaging of ACATS are unverified** — check before
counting on it.

## Log
- 2026-08-09 — noted. Track letter L (Legacy) agreed for Ada + COBOL; CLAUDE.md
  section deferred until the lane has code.
