---
track: A
prio: 50
type: bug
summary: "`make compiler/pascal26` seeds from ./compiler/pascal26, which has no frozen RTL and resolves `uses builtinheap` from the LIVE tree — so it links tomorrow's RTL into today's emitter. Any RTL layout change silently produces a compiler that builds fine and then dies"
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

## Fix — options, not yet decided

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

(2) plus (3) is probably right — (3) alone is worth it regardless, because it
turns this whole class of failure from "mystery crash two generations later"
into one line of output.

## Gate

Track A. The change is to the build path itself, so the test is a deliberate
layout bump: make a trivial incompatible change to the managed header, confirm
the seed **refuses or copes** rather than producing a core-dumping compiler, then
revert. Plus the ordinary `gate.sh quick` and a `make compiler/pascal26` from a
clean tree.
