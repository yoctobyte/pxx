---
slug: feature-a-fold-the-consensus-dead-branch-core-at-every-level
track: A
prio: 65
type: feature
status: open
blocked-by: []
found: 2026-08-31
found-by: frank-user
owner: ""
summary: "Implements the ruling in decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0. Fold the CONSENSUS CORE at every level including -O0 -- a condition constant in the expression itself (literal, sizeof comparison, short-circuit against a literal) and statements after a return -- because all three of gcc, clang and tcc do, and tcc has no optimizer, so this is LOWERING and does not spend -O0's byte-identity property. HARD CONSTRAINT, measured: prune only when unreachable AND the address does not escape; a dead arm holding a label whose address is taken is kept by all three at every level, and an if-only test will not catch getting this wrong. Unblocks feature-c-corpus-busybox-applet. Also adds -OO for the true source-1:1 build, as a NAMED FLAG not a level."
---

# Fold the consensus dead-branch core at every level

Implements `decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0`
(ruled by the owner 2026-08-31). Read the ruling for the three-compiler
measurement; this ticket is the work.

## Symptom this closes

```
-O0: symbol lookup error: undefined symbol: NEVER_stmt   (exit 127)
-O1/-O2/-O3: fine
```

`IROptDeadCode` and `IROptConstBranch` live in `IROptimize`, gated at
`ir_codegen.inc:11332` behind `if OptLevel >= 1`, so `-O0` has never pruned any
dead code. The binary links, warns, and dies before `main`.

## What to build

**1. The consensus core, at every level.** Fold a condition that is constant *in
the expression itself* — literal, `sizeof` comparison, short-circuit against a
literal — and drop statements after a `return`. This belongs in **lowering**, not
in `IROptimize`; leave the `OptLevel >= 1` gate exactly where it is. Both
frontends and all six backends inherit it from shared IR.

**2. The address-escape guard — do not skip this.** Prune only when the arm is
unreachable **and** no label inside it has had its address taken:

```c
void f(void){ void *p = &&inside; if (0) { inside: N(); } goto *p; }
```

gcc, clang and tcc all **keep** `N` here, at every level. Pruning on
reachability alone silently breaks computed-goto code.

**3. `-OO` — the true source-1:1 build**, as a named flag, never a level below
zero (`decided/decide-the-o-level-charter`: trade-offs are not levels). This is
the byte-identity reference used to separate a lowering bug from an optimizer
bug, which is the whole reason `-O0`'s charter existed; it moves here rather than
disappearing.

**4. Amend the charter line.** `-O0 = zero optimization, source 1:1` becomes
`-O0 = zero optimization` with 1:1 pointing at `-OO`. Amend it in the open, do
not quietly violate it.

## Out of scope for the core

Constant propagation through a variable (`const int z = 0; if (z)`) — gcc and tcc
keep it, clang prunes it, so nothing portable relies on either answer. The
ruling leaves *diagnose vs quietly emit* here to this ticket; a hard compile-time
error is defensible and costs no real code.

## Acceptance

- The busybox `xatonum.h` shape links and runs at **every** level, `-O0` included.
- The computed-goto case above still resolves `N_addrtaken` at every level.
- `while (0) { N(); }` and `return; N();` both covered — a fix touching only `if`
  will miss them, **and no `if`-only test will say so** (measured in the parent).
- Self-host fixedpoint unchanged; `-OO` reproduces today's `-O0` bytes.
- Cross targets: unmeasured everywhere in this chain. Carry a one-line repro per
  frontend the quick tier does not cover.

## Unblocks

[[feature-c-corpus-busybox-applet]] — the corpus this was found closing.
