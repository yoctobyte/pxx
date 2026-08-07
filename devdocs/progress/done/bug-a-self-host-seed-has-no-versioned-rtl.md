---
track: A
prio: 20
type: bug
summary: "`make compiler/pascal26` has no versioned RTL, so an RTL LAYOUT change links tomorrow's RTL into today's emitter and yields a compiler that builds fine then dies. Rare and now documented — the wanted fix is a cheap version stamp that refuses, not a reworked seed path"
status: done
owner: claude-AN
---

# The self-host seed carries no versioned RTL

- **Type:** bug (build/bootstrap hazard) — **Track A**
- **Found:** 2026-08-07, landing [[feature-a-managed-block-kind-word]], and
  confirmed by measurement after the user challenged the workaround.

## The hazard

A compiler binary has two things that must agree about any runtime data layout:

1. the **inline code it emits** for its own constructs (header offsets are
   compiled into it), and
2. the **RTL it links** (`builtinheap.pas` and friends).

`pinned` keeps these in step by construction: `make pin` freezes
`compiler/builtin/*.pas` into `stable_linux_amd64/default/builtin/`, and the
pinned binary resolves `uses builtinheap` from its own ExeDir in preference to
the live tree. Its emitter and its RTL are the same vintage.

**`./compiler/pascal26` has no such snapshot.** It resolves `uses builtinheap`
from the live tree. So the moment the RTL's layout changes under it, the next
`make compiler/pascal26` builds a compiler whose inline codegen assumes the OLD
layout and whose linked RTL implements the NEW one.

## Why it is worse than a build break

Measured with the managed-block header change (16 → 24 byte header):

| seed | result |
| --- | --- |
| `./compiler/pascal26` (live RTL) | compiles the source **fine**, exit 0 — and the binary it produces **dumps core** |
| `pinned` (frozen RTL beside it) | works; B → C → D reaches a fixedpoint, byte-identical to an FPC-seeded build |

The compile *succeeds*. Nothing looks wrong until the product runs, and
`make compiler/pascal26` iterates to convergence, so the crash lands in round 2
and reads as a codegen bug in whatever the change touched. That is a very
expensive way to learn this.

It also produced a wrong conclusion in the ticket above before it was measured
properly: "a header change cannot self-host, seed from FPC". It can. The FPC
detour cost a session's caution and was avoidable.

## Scope: this is a GUARD, not a rework (user, 2026-08-07)

`compiler/pascal26` is the fast path and should stay the default — the RTL
seldom changes in ways that matter, and paying a slower seed every day to insure
against a rare event is the wrong trade. The workflow doc
(`devdocs/dev/fpc-optional-workflow.md`) now records when to reach for seed 2
instead, and that recording is most of the value here.

What remains worth building is only option 3 below: a stamp that turns the
silent core dump into one line of output. Options 1 and 2 are recorded for
completeness and are **not** the ask.

## Fix — options

1. **Seed the self-host rule from `pinned`** rather than from
   `./compiler/pascal26`. Simplest, and it is already what `gate.sh` does. Cost:
   the daily loop's first generation comes from the pin rather than from the last
   build, which may slow convergence by a round.
2. **Give the working compiler a frozen RTL too** — snapshot `compiler/builtin/`
   beside `compiler/pascal26` whenever it is rebuilt, mirroring the pinned
   mechanism. Keeps the fast local loop, closes the gap generally.
3. **Detect and refuse**: stamp the RTL layout version into both the binary and
   the source, and have the seed abort when they disagree. Does not fix it, but
   converts a silent core dump into a message naming the cause.

**(3) is the ask.** It is cheap, it keeps the fast path fast, and it converts
this whole class of failure from "mystery crash two generations later" into a
message naming the cause. (1) and (2) would both tax the daily loop to prevent
something that happens about once a year.

## Gate

Track A. The change is to the build path itself, so the test is a deliberate
layout bump: make a trivial incompatible change to the managed header, confirm
the seed **refuses or copes** rather than producing a core-dumping compiler, then
revert. Plus the ordinary `gate.sh quick` and a `make compiler/pascal26` from a
clean tree.

## FIXED 2026-08-07 — option 3 (the ask), as scoped

`PXX_RTL_LAYOUT_VERSION` now exists twice:

- `compiler/defs.inc` — the layout this compiler's inline codegen **emits**;
  compiled into the binary.
- `compiler/builtin/builtinheap.pas` — the layout the RTL **implements**.

`ParseUsesUnit` compares them when it links `builtinheap` and refuses a
mismatch. Both constants carry the "bump these together" note, on both sides.

Options 1 and 2 were **not** built, per the scope note: the fast path stays the
fast path.

### A MISSING constant is not a mismatch

Deliberate, and load-bearing: every frozen builtin that predates the stamp — the
currently pinned one included — has no such constant, and refusing those would
break every build that uses them. Absent = unknown = allowed; only a
present-and-different number is refused. Verified: the pinned binary (whose
frozen `builtinheap.pas` contains zero occurrences of the name) still builds
`hello.pas` and runs it.

### Measured — the gate's own test, a deliberate layout bump

Bumped the RTL's constant to 2 while the compiler still emitted 1:

```
pascal26:2: error: RTL layout mismatch: this compiler emits code for layout
version 1 but the builtinheap it is linking implements version 2. The seed
binary predates a runtime layout change, so it would build a compiler that
compiles clean and then crashes. Reseed: `make seed-from-stable` (or build from
FPC) and retry
```

Refused for a plain `hello.pas` **and** for `compiler/compiler.pas` — i.e. the
self-host seed, which is the case that cost a session. Reverted, and both the
current and the pinned compiler build and run normally again.

### No re-pin needed

Adding a constant changes no emitted code, and the guard tolerates the pin's
stamp-less frozen copy, so `gate.sh quick` was GREEN on the first run. The next
ordinary `make pin` picks the stamp up on its own; forcing one now would spend
the deliberate brake for nothing.

`devdocs/dev/fpc-optional-workflow.md` updated: the "use seed 2 for a layout
change" note now says the seed will tell you, and that the two constants are
bumped together.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN, plus the deliberate-bump test above.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
