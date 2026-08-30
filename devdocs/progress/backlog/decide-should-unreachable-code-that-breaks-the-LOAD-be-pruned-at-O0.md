---
track: U
prio: 45
type: decide
status: open
found: 2026-08-30
found-by: frankS
summary: "Dead-code elimination lives entirely in IROptimize (-O1+), so at -O0 a provably-unreachable arm is still emitted — and when its call names a symbol nothing defines, the binary does not START. Fixed at -O1/-O2/-O3 by the const-branch pass; -O0 still fails, including on the statement-level shape. The fork: -O0's documented contract is 'raw lowering, byte-identical reference', and pruning is the one thing that contract forbids. Two documented goods in conflict; the owner's call, not mine."
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
