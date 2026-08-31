---
track: U
prio: 65
type: decide
status: decided
found: 2026-08-30
found-by: frankS
summary: "RULED 2026-08-31 by the owner: PRUNE, at every level including -O0, following the de-facto standard the way FPC does. Measured against three independent implementations (gcc 13.3 + 15.2, clang 21.1.8, tcc 0.9.27, x86-64 Linux): ALL prune the busybox xatonum.h idiom at every level, tcc included -- and tcc has no optimizer, so folding a syntactically-constant condition and dropping statements after a return is LOWERING, not optimization. -O0's byte-identity charter is therefore not spent by doing it, which is what the original three options all assumed. Outside that consensus core the three disagree in three different ways, so nothing portable relies on it and we are free to diagnose. HARD CONSTRAINT, measured: a dead arm containing a label whose ADDRESS IS TAKEN is kept by all three at every level -- the rule is 'unreachable AND address does not escape'. True source-1:1 becomes a NAMED FLAG (owner's spelling: -OO), never a level, per decide-the-o-level-charter. C99 6.9p5 makes the construct UB, so pruning and rejecting both conform: this is a choice, not obedience. Implementation: feature-a-fold-the-consensus-dead-branch-core-at-every-level."
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

---

# RULED 2026-08-31 — prune, and the charter was never the obstacle

Owner's call, after the measurement below: **we follow de-facto standards, as
FPC does.** We want busybox, the idiom is what real C does, and a general C
compiler compiles general C.

## What was measured, and why it changes the question

The three options above all share one premise: that pruning at `-O0` spends the
byte-identity property `-O0` exists to provide. **The premise is false**, and one
compiler proves it.

Same six shapes, `-O0`, symbol left referenced in the `.o` (`nm -u`):

| shape | gcc 13.3 / 15.2 | clang 21.1.8 | tcc 0.9.27 |
| --- | --- | --- | --- |
| `if (0) N();` | pruned | pruned | pruned |
| `if (sizeof(long)!=8) N();` | pruned | pruned | pruned |
| `return; N();` | pruned | pruned | pruned |
| `const int z=0; if (z) N();` | **kept** | pruned | **kept** |
| `while (0) N();` | pruned | **kept** | pruned |
| `if (ext_fn() && 0) N();` | pruned | **kept** | pruned |

And the actual busybox `include/xatonum.h:161` shape, verbatim from the upstream
tree in `library_candidates/busybox`: **pruned by all three, at every level.**

**tcc is the load-bearing measurement.** It has no SSA, no pass pipeline, no
optimizer worth the name, and it ignores `-O`. If tcc never emits the reference,
then folding a `sizeof` comparison and dropping the tail after a `return` is not
optimization — it is what lowering C to machine code does. So `-O0` can do it and
still be the raw lowering. The charter line `-O0 = zero optimization, source 1:1`
was never in conflict with this; it was in conflict with a misclassification.

Corollary worth stating plainly: **no shipping compiler's `-O0` is source 1:1.**
Ours was stricter than gcc's, clang's and tcc's.

## The consensus core — what we implement

A condition that is **constant in the expression itself** (literal, `sizeof`
comparison, short-circuit against a literal), and **statements after a `return`**.
All three implementations, every level. This is the set busybox needs.

Explicitly NOT in the core: constant *propagation through a variable*
(`const int z = 0; if (z)`). gcc and tcc keep it, clang prunes it — the three
real compilers already disagree, so no portable code can rely on either answer
and we are free. A hard compile-time diagnostic there is defensible and costs no
real code; that is the owner's strictness instinct, scoped to where it is free.

## HARD CONSTRAINT — address escape (owner's counterexample, measured)

The owner raised code entered by a computed jump rather than by control flow. It
is real, and there is a precise version of it:

```c
void f(void){
    void *p = &&inside;
    if (0) { inside: N_addrtaken(); }   /* unreachable by control flow */
    goto *p;                            /* ...reached anyway */
}
```

| | gcc -O0/-O2 | clang -O0/-O2 | tcc |
| --- | --- | --- | --- |
| plain dead arm | pruned | pruned | pruned |
| dead arm, label address taken | **kept** | **kept** | **kept** |

Unanimous, in both directions — the only shape in this whole investigation that
all three agree on twice. **So the rule is not "unreachable"; it is "unreachable
AND its address does not escape".** An implementation that prunes on reachability
alone breaks computed-goto code and no `if`-only test will say so.

Genuine self-modifying code is a separate matter and needs no rule: writing to
your own code pages is outside C's abstract machine entirely (`mprotect` is not
in the language), so it is off-spec before pruning is reached.

## True 1:1 becomes a FLAG, not a level

`-O0` joining everyone else leaves the genuinely-1:1 build — the byte-identity
reference used to tell a lowering bug from an optimizer bug — needing a name.
Owner's spelling: **`-OO`**. It must be a **named flag, not a level below zero**,
and that is already ruled: `decided/decide-the-o-level-charter` — *"Trade-offs are
NOT a level... an author chooses WHICH trade, not HOW MUCH."*

The reference is why `-O0`'s charter was written, and it survives — it moves to a
flag instead of being the default nobody else ships.

## C99 says we are choosing, not obeying

C99 §6.9p5: if an identifier with external linkage **is used in an expression**,
there shall be exactly one external definition somewhere in the program. "Used in
an expression" is syntactic — unreachability does not exempt it. This is a `shall`
outside a constraint, so the construct is **undefined behaviour, no diagnostic
required**.

Both behaviours therefore conform: gcc pruning it is quality-of-implementation in
UB territory, and rejecting it would have been equally standard-conforming. The
three-way disagreement in the table above is that surface doing exactly what it
was designed to do. **So "gcc does it" was never an argument — three independent
implementations doing it, one of them with no optimizer, is.**

## Not decided here

The strictness question outside the consensus core (diagnose vs quietly emit) is
left to the implementation ticket. Cross-target behaviour is unmeasured — all of
the above is x86-64 Linux.

*Measured 2026-08-31 by frank-user at the owner's request; clang and tcc were
installed on this box for it. Ticket ruled in the same session.*
