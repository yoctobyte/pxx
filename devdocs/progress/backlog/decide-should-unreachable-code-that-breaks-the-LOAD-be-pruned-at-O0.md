---
track: U
prio: 65
type: decide
status: open
found: 2026-08-30
found-by: frankS
summary: "RE-PRICED 45 -> 65 2026-08-30 with the evidence below: re-measured at HEAD (d650d1480) it is still exit=127 at -O0 against the LANDED pass, gcc links and runs at every level, and two agents independently price the same option first. Dead-code elimination lives entirely in IROptimize (-O1+), so at -O0 a provably-unreachable arm is still emitted — and when its call names a symbol nothing defines, the binary does not START. Fixed at -O1/-O2/-O3 by the const-branch pass; -O0 still fails, including on the statement-level shape. The fork: -O0's documented contract is 'raw lowering, byte-identical reference', and pruning is the one thing that contract forbids. Two documented goods in conflict; the owner's call, not mine."
---

# Should unreachable code that breaks the LOAD be pruned at -O0?

Fallout from
[[bug-a-a-constant-if-condition-keeps-its-dead-arm-and-the-binary-will-not-start]],
which is fixed at every level the default reaches. This is the residue.

## Measured, at the fix's HEAD

```
-O0: symbol lookup error: undefined symbol: NEVER_stmt
-O1: 42 42 42 42 42
-O2: 42 42 42 42 42     <- the default
-O3: 42 42 42 42 42
```

Note **which** symbol -O0 dies on: `NEVER_stmt`, the plain
`return A; return NEVER();` shape that the original ticket lists as *already
working*. It works at -O1+ only. `IROptDeadCode` has always lived in
`IROptimize`, so **-O0 has never pruned any dead code at all** — this is not a
gap the const-branch fix opened, it is one it made visible.

## The fork

- **-O0's contract is deliberate**: *"gated here so -O0 emits the raw lowering
  byte-identically"* (`ir_codegen.inc`). It is the byte-identity reference used
  to tell a lowering change from an optimisation change. Pruning is precisely
  the thing that reference must not do.
- **But this failure is not a performance matter.** The program does not run
  slower, it does not start. gcc prunes it at `-O0`. A user who selects -O0 is
  opting out of optimisation, and it is not obvious they are also opting into
  a binary that cannot load.

## Options

1. **Leave it.** -O0 keeps its guarantee; document that -O0 can emit a
   reference to a declared-but-undefined symbol in unreachable code. Cheapest,
   and the default (-O2) is correct.
2. **Run only the const-branch + reachability prune at -O0**, keeping the rest
   of `IROptimize` gated. Fixes the load failure everywhere; costs the exact
   byte-identity property -O0 exists to provide.
3. **Prune only when the dead call names an undeclared/external symbol.** Fixes
   the observable without touching ordinary -O0 output — but it makes -O0's
   output depend on a symbol property, which is a third rule to maintain and the
   kind of special case `normalise-dont-special-case.md` warns about.

**Recommendation: (1).** The default is -O2 and is correct; the corpus that
motivated the parent ticket builds at the default; and -O0's byte-identity
reference is load-bearing for diagnosing miscompiles, which is a rarer but much
more expensive activity than compiling at -O0 for release. But this trades two
documented goods against each other, so it is the owner's call and not mine.

---

## Merged in from a DUPLICATE the coordinator filed (2026-08-30)

I filed `decide-is-deleting-a-provably-unreachable-branch-an-optimization-or-a-
correctness-requirement` without seeing this ticket, because I misread
`c9a1f6f2a`'s body line *"frankC's p70"* as naming its AUTHOR rather than the
TICKET it closes — so I never looked at what that commit added, and it added
this file. **Duplicate deleted; its content is below. `found-by: frankS` is
correct and unchanged.**

### The mechanism, verified at the source

`compiler/ir_codegen.inc:11332`:

```pascal
{ -O1+ shared-IR optimization pipeline (see ir.inc / IROptimize). Gated here
  so -O0 emits the raw lowering byte-identically; runs after IRVerify (on
  validated IR) and before IRDump so `--dump-ir` shows the optimized form. }
if OptLevel >= 1 then IROptimize;
```

So `IROptConstBranch` and the label liveness in `IROptDeadCode` cannot fire at
-O0 **by construction**. This is deliberate and implements the O charter's
`-O0 = zero optimization, source 1:1` (`decided/decide-the-o-level-charter`).

### The gcc oracle (frankA)

```
gcc  -O0 / -O1 / -O2    links and runs, exit 0   (never references the symbol)
pxx  -O0                undefined symbol, exit 127
pxx  -O1 / -O2 / -O3    42, exit 0
```

**Re-measured at HEAD against the LANDED pass** (frankA, binary `f692ff3af0f6`,
sha `d650d1480`): `while False` with an undefined external gives **127 / 0 / 0 /
0** across -O0..-O3. So the premise holds against what shipped, not merely
against a parked branch — that was the open question.

### Two independent approaches hit the same wall

frankS's landed const-branch pass is -O1+ because `IROptimize` is. frankA's
lowering-based fold collapses the `if` into `return A; return NEVER();` — and
pruning *that* is `IROptDeadCode`'s job, also -O1+. **One cause: the only thing
that deletes unreachable code is switched off at -O0.** One approach failing is
a bug in the approach; two failing at the same gate is the gate.

### The options as I framed them

1. **CORRECTNESS** — run a minimal reachability prune unconditionally (or a
   -O0-safe subset: fold a decidable branch condition, drop the orphaned arm,
   nothing else). Cost: -O0 is no longer literally source 1:1, and the charter
   line needs **amending rather than quietly violating**.
2. **OPTIMIZATION** — -O0 keeps its promise and cannot compile the static-assert
   idiom. Cost: -O0 cannot build busybox, and the level people debug at is the
   one that fails at load.
3. **EMISSION PROPERTY** — keep `IROptimize` at -O1+, but stop *codegen* emitting
   an external reference for a call in a provably dead arm. Reachability becomes
   an emission property rather than a pass; fixes -O0 without touching the
   charter. **frankA and frankC independently price this one first.**

### Sibling shape, measured

`while (0) { NEVER(); }` in C and `while False do ... NEVER` in Pascal both die
at load. A fix touching only `if` will not cover it, **and no `if`-only test
would say so.**

### Not in scope

Whether `c9a1f6f2a` was right. It was, and it unblocked busybox at every
shipping level.
