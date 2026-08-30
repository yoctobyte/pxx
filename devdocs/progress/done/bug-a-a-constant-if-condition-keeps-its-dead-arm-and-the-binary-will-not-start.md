---
track: A
prio: 70
type: bug
status: done
found: 2026-08-30
found-by: frankC
owner: frankS
---

# A constant `if` condition keeps its dead arm, and the binary will not start

`jump_if_false` on a `const_int` is never folded, and the block it guards is
never pruned. The dead arm reaches codegen, so a call inside it becomes a real
external reference — and if that symbol is only ever *declared*, the program
gcc builds and runs fine becomes one that **fails at load**:

```
symbol lookup error: ./a.out: undefined symbol: NEVER_DEFINED_marker
```

Not a warning-level nuisance: the compiler does warn (`crtl does not define
...`), links anyway, and the binary dies before `main`.

## Repro

```c
int NEVER_DEFINED_marker(void);              /* declared, never defined */
static int pick(unsigned x) {
  if (1) return (int)x + 1;                  /* always taken */
  return NEVER_DEFINED_marker();             /* unreachable */
}
int main(void) { printf("%d\n", pick(41)); return 0; }
```

gcc prints `42`. pxx (default *and* `-O2`) emits the call and the binary will
not start.

## It is the IR, not a frontend

`PXXDBG=a.ir:pick` shows the condition is already a literal:

```
0: const_int ival=1
1: jump_if_false a=0            <- operand is a constant; never taken
...
BB4: 20: call a=394             <- survives to codegen anyway
```

The Pascal frontend reproduces it exactly (`if True then ... Exit;` then a call
to an `external name` that does not exist → same load failure), so this is
shared-IR ground and one fix covers every frontend.

## The boundary, measured

| shape | dead call emitted? |
| --- | --- |
| `return A; return NEVER();` | **no** — statement-level unreachable IS pruned |
| `if (1) return A; return NEVER();` | yes |
| `if (0) return NEVER(); return A;` | yes |
| `if (sizeof(unsigned) == 4) return A; return NEVER();` | yes |

So there is unreachable-code elimination, it just does not run after constant
folding: even a literal `if (1)` keeps both arms.

## Why it is worth 70

This is the pre-C11 static-assert idiom, and it is everywhere in real C.
busybox's `include/xatonum.h` uses it verbatim:

```c
uint32_t BUG_bb_strtou32_unimplemented(void);      /* never defined, anywhere */
static ALWAYS_INLINE uint32_t bb_strtou32(...) {
	if (sizeof(uint32_t) == sizeof(unsigned)) return bb_strtou(...);
	if (sizeof(uint32_t) == sizeof(unsigned long)) return bb_strtoul(...);
	return BUG_bb_strtou32_unimplemented();        /* the assert */
}
```

The first condition is true on every target we have, so gcc never references
the symbol. We do, and `busybox cat` therefore cannot start — found while
closing the TU set for `feature-c-corpus-busybox-applet`, which it blocks.
Defining the symbol in crtl would be the wrong fix twice over: it is busybox's
private assert, and the next corpus brings its own spelling.

---

## FIXED 2026-08-30 (frankS) — two passes, and the second was not in the diagnosis

Shared IR, so both frontends and all six backends get it from one change.

### What was actually wrong — three things, not one

1. **A constant condition was never acted on.** `IROptConstBranch` (new, runs
   first in `IROptimize`) folds `IR_JUMP_IF_FALSE` on a decidable condition:
   true -> the branch never fires, NOP it; false -> it *is* an unconditional
   jump. It does not fold anything else — the real work is handed to
   `IROptDeadCode`, which is exact.

2. **An ORPHANED LABEL resurrected the arm, and this was not in the ticket.**
   `IROptDeadCode` treated *any* `IR_LABEL` as a live jump target — true of a
   label some jump names, false of the else-label left behind once the only
   branch naming it is folded away. Without this the fold changed nothing: the
   branch vanished, the then-arm still ended in a return, and the dead call was
   still emitted because a label with no predecessors reset the reachability
   walk. Label liveness now reads its node-kind set (`IR_JUMP`,
   `IR_JUMP_IF_FALSE`, `IR_EXC_ENTER`, `IR_EXC_MATCH`, `IR_EXC_MATCH_HIT`) off
   **`IRVerify`**, which validates every kind — so a future label-consuming op
   cannot be added without a case arm landing next to those. That is deliberate:
   the pass's own correctness note warns that a label-set assembled by grep is
   how it would silently delete a live target.

3. **One round is provably not enough.** The then-arm's `jump endLabel` sits
   *after* that arm's own `return`, so it is itself dead — but it still reads as
   a live reference when the mark pass runs, which keeps `endLabel` alive, which
   keeps the arm. Round 2 sees the jump already NOPed and the label falls with
   it. Measured on this repro: round 1 removes the branch and the else-label,
   round 2 removes the call. Terminates because every round only turns nodes
   *into* NOPs — monotone, so it cannot oscillate.

### The fourth shape needed a premise in ir.inc to be retired

`if (sizeof(unsigned) == 4)` lowers to `const_int 4; const_int 4; binop tkEq`.
`ir.inc`'s 2026-07-03 note says IR const-folding was implemented, measured at
**zero fires**, and rejected because *"no const-const IR_BINOP ever reaches the
IR for ANY frontend"*. **Measured false, in both frontends, for the most
ordinary shape there is:** C's `sizeof(unsigned) == 4` and Pascal's
`SizeOf(LongInt) = 4` produce byte-identical const-const binops. `SizeOf` is the
producer the note said to watch for and it was already there — both frontends
fold the operand and neither folds the comparison around it.

`IRConstCondValue` is that revival, scoped to the one question a branch asks and
to **`=` and `<>` only**. Those are the idiom in the wild and are decidable from
the bit patterns, with no signedness question to get wrong; the ordered
comparisons would need the operand type kinds consulted, and a wrong guess there
*silently inverts a branch* — a worse defect than the missed fold it buys.

### Gate

Self-host fixedpoint `082124d3e1a6`, `gate.sh quick`, and:

| oracle | result |
| --- | --- |
| the ticket's repro | `42` (was: will not start) |
| the ticket's **whole boundary table**, all four shapes, vs **gcc** | `42 42 42 42` — identical |
| busybox's `xatonum.h` assert verbatim, vs gcc | `42` — identical |
| Pascal `if True` / `if False` / `if SizeOf(LongInt)=4` | all `42` |
| **negative control** — `==`/`!=`/`<>` on a RUNTIME value, vs gcc | `100 200 400 300 500 600` — identical |
| control-flow torture (if/else, for+break+continue, try/except, case, while True) on **x86-64, i386, aarch64, arm32, riscv32** | all `2 3 4 5 6 20 8` |
| the same, minus exceptions, on **xtensa** under qemu | `2 3 4 5 20 8` |

The cross-target rows are there because this is a shared-IR pass and the
self-host gate builds **one** backend: it is not evidence for the other five, so
they were run rather than assumed.

### Regression

`test/c_const_branch_dead_arm.c` and `test/test_const_branch_dead_arm.pas`, both
wired into `make test`. **The undefined symbols in both are load-bearing**: a
regression does not produce a wrong number, it produces a binary that will not
start. Defining them would delete the test while leaving it green, and both
files say so. Each carries the negative-control row too — the half that says the
pass is narrow rather than merely effective.

Note for whoever reads the Pascal one: **fpc 3.2.2 does not prune these arms
either** and fails to link that file outright. gcc is the oracle here, not FPC,
and the C file is what diffs against it.

## Log
- 2026-08-30 — resolved, commit c9a1f6f2a.
