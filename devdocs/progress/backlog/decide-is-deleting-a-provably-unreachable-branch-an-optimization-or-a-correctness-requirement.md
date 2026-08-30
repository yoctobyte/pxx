---
track: U
prio: 70
type: decide
status: backlog
owner: unassigned
blocked-by: []
summary: "A constant `if` guarding a call to a DECLARED-but-never-DEFINED symbol makes the binary fail at LOAD -- the pre-C11 static-assert idiom, which busybox uses. Fixed for -O1+ in c9a1f6f2a (IROptConstBranch + label liveness in IROptDeadCode), and the ticket is in done/. It is STILL BROKEN AT -O0, by construction: ir_codegen.inc:11332 reads `if OptLevel >= 1 then IROptimize` -- gated deliberately, so `-O0 emits the raw lowering byte-identically`, which is the O charter's `-O0 = zero optimization, source 1:1`. gcc links and runs at -O0/-O1/-O2; pxx -O0 exits 127 with an undefined symbol. So the fork is REAL and not a bug: is deleting a provably-unreachable branch an OPTIMIZATION (stays -O1+, and -O0 cannot build busybox) or a LOWERING CORRECTNESS requirement (runs always, and -O0 is no longer source 1:1)? Measured by frankA, mechanism verified by the coordinator. Two independent fix approaches hit the same residue for the same cause."
---

# Decide: is deleting a provably-unreachable branch an optimization, or a correctness requirement?

- **Type:** decision (Track U) — filed by the coordinator, 2026-08-30, on frankA's
  measurement. **frankA identified the fork and stood down rather than resolving it
  unilaterally**, which is why this ticket exists rather than a second fix.

## The measurement

frankA, with a gcc oracle, both languages:

```
gcc  -O0 / -O1 / -O2    links and runs, exit 0   (never references the symbol)
pxx  -O0                undefined symbol, exit 127
pxx  -O1 / -O2 / -O3    42, exit 0               (with c9a1f6f2a in)
```

The `while` sibling behaves identically: `while (0) { NEVER(); }` in C and
`while False do ... NEVER` in Pascal both die at load.

## The mechanism — verified, and it is deliberate

`compiler/ir_codegen.inc:11332`:

```pascal
{ -O1+ shared-IR optimization pipeline (see ir.inc / IROptimize). Gated here
  so -O0 emits the raw lowering byte-identically; runs after IRVerify (on
  validated IR) and before IRDump so `--dump-ir` shows the optimized form. }
if OptLevel >= 1 then IROptimize;
```

So `IROptConstBranch` and the label liveness in `IROptDeadCode` **cannot fire at
-O0 by construction**. This is not an oversight: it implements the O charter's
`-O0 = zero optimization, source 1:1` (`decided/decide-the-o-level-charter`).

**Two independent approaches hit the same residue.** frankC's landed const-branch
pass is -O1+ because `IROptimize` is. frankA's lowering-based fold collapses the
`if` into `return A; return NEVER();` — and pruning *that* is `IROptDeadCode`'s
job, which is also -O1+. **One cause: the only thing that deletes unreachable
code is switched off at -O0.**

## The fork

The closed ticket's own framing is **a program that will not start is not an
optimization question** — and `-O0` is the level a person reaches for when
debugging exactly this kind of failure. Against that, `-O0 = source 1:1` is a
ruled property that something must give up.

- **Option 1 — it is CORRECTNESS.** Run a minimal reachability prune
  unconditionally (or a `-O0`-safe subset: fold a decidable branch condition and
  drop the orphaned arm, nothing else). Cost: `-O0` is no longer literally source
  1:1, and the charter line needs amending rather than quietly violating.
- **Option 2 — it is OPTIMIZATION.** `-O0` keeps its promise and cannot compile
  the static-assert idiom. Cost: `-O0` cannot build busybox, and the level people
  debug at is the one that fails at load.
- **Option 3 — narrow it to the emitter.** Keep `IROptimize` at -O1+, but stop
  *codegen* from emitting an external reference for a call in a provably dead
  arm. Reachability becomes an emission property rather than a pass. Unpriced.

**Recommendation (coordinator):** option 3 if it is as small as it looks, else
option 1 with the charter line amended in the same commit — because the failure
is a **won't-start**, not a slow program, and the charter never contemplated
`-O0` producing a binary that cannot load. But this is the owner's call: it
changes what a documented `-O` level means.

## Not in scope

Whether `c9a1f6f2a` was right — it was, and it unblocked busybox at the shipping
levels. This is only about `-O0`.
