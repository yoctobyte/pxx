---
track: A
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: frankC
owner: frankS
---

# A loop in dead code keeps itself alive through its own back edge

`IROptDeadCode` decides reachability with a linear scan, reviving it at any
label some jump still references. A loop's back-edge label is referenced **by
the loop's own back-jump**, which sits inside the dead region — so a dead loop
is its own witness and survives.

Same consequence as its sibling
`bug-a-a-constant-if-condition-keeps-its-dead-arm-and-the-binary-will-not-start`:
a call in the surviving region is a real external reference, so a
declared-but-never-defined symbol makes the binary **fail at load**.

## Repro and boundary (`-O2`, gcc prints `0` for every row)

```c
int NEVER_W(void);                      /* declared, defined nowhere */
int main(void){ int n = 0; <BODY> }
```

| BODY | pxx |
| --- | --- |
| `printf("%d\n",n); return 0; n += NEVER_W(); return n;` | **0** |
| `printf("%d\n",n); return 0; while(1){ n += NEVER_W(); }` | LOAD-FAIL |
| `if(sizeof(int)==4){printf("%d\n",n);return 0;} while(1){...}` | LOAD-FAIL |
| `... for(;;){...}` / `... while(n<3){...}` | LOAD-FAIL |

The first two rows are the whole finding: **a plain statement after a `return`
is pruned; a loop after the same `return` is not.** Nothing about a constant
condition is involved, so this **predates** the const-branch work and is not a
regression from it — the last row above needs no `if` at all.

`while(0)` / `for(;0;)` and Pascal's `while False` are all fine; those are the
const-condition case and `IROptConstBranch` already handles them.

## Why the linear scan cannot fix this

"Referenced by some jump" is not "reachable". The scan has no notion of where
control enters, so it cannot distinguish a label reached from the entry from
one reached only from inside the region it is deciding about. Iterating does
not help either: the back-jump never dies, because the pass keeps its label
alive, which keeps the jump alive.

The fix is a **worklist from the entry** — mark the first node reachable, follow
every jump and fall-through, and NOP what was never marked. That subsumes the
existing scan and the label-liveness scan both, and it deletes cases rather than
adding them (`root-cause-over-microfix`). It also needs the same correctness
note the current pass carries: every control-transfer landing site must be a
stream `IR_LABEL`, which holds while PXX has no computed jumps.

Not urgent — no corpus is blocked on it (busybox's applet closure is clear), and
`-O0` already exposes a wider version of the same class
(`decide-is-deleting-a-provably-unreachable-branch-an-optimization-or-a-correctness-requirement`).

## The sibling to check with it (frankA, 2026-08-30)

A **backward `goto` into a dead region** is the same self-witnessing shape: the
label is referenced by a jump that itself sits in the region being decided. If
the fix is a worklist from the entry, both fall out of it and neither needs its
own case — which is the argument for pricing the worklist over adding a third
scan. `test/c_const_branch_dead_arm.c` already carries a goto row, added as a
control against an over-eager fold; it is green today and would stay green.

## Resolution (frankS, 2026-08-30): the worklist, and it DELETED a pass

Fixed as the ticket priced it — reachability from the entry, replacing the
reference count rather than extending it. All four repro rows now print `0`,
matching gcc, and so does the backward-`goto` sibling.

`IRMarkReferencedLabels` is **gone**, not amended. `IRMarkReachableLabels`
replaces it and subsumes both it and the separate orphaned-label rule, so an
orphaned else-label from a folded constant branch and a dead loop's back edge
are now the **same fact** — a label nothing reachable reaches — instead of two
mechanisms answering one question. `IROptDeadCode` lost its own `repeat` loop in
the process: net one fixpoint where there were two, and one concept where there
were three.

### The one design constraint, and it is not stylistic

**Mark to a fixpoint FIRST, remove ONCE.** Fusing the two — the obvious way to
write it, and the shape the old pass had — is a real bug, not untidiness: a
round that NOPs a node it believes unreachable cannot un-NOP it when a later
round discovers a forward jump into that region. The two directions are
monotone in *opposite* senses (labels only get added, nodes only get removed),
so they cannot share a loop. The marking pass is now explicitly marking-only and
says why.

Termination: the label set only grows, so at most `IRLabelCount` rounds; two in
practice. The removal walk is a single linear pass. Self-compile is **33.0s**
against 34.4s and 37.7s measured earlier the same session on the same box, same
fixedpoint hash both sides of the timing — one walk replacing a repeat-walk, so
if anything it is cheaper.

### The invariant now carries more weight, and the comment says so

Reachability-from-entry deletes **strictly more** than a reference count did.
An unreferenced-but-reachable landing site used to be saved by the old "any
IR_LABEL resets the walk" rule and is not any more, so the pass's existing
correctness invariant — *every control-transfer landing site is a stream
IR_LABEL* — is doing more work than it was. That is written into the pass, next
to the computed-jump warning it already carried.

### Evidence

`test/c_dead_loop_back_edge.c` and `test/test_dead_loop_back_edge.pas`, both
wired into `make test`. Each carries **d0**, the plain statement after the return
that already worked, sitting beside d1 so the difference reads as the loop and
not as the unreachability; the `while`/`for`/`while(cond)`/`do-while` and
`while True`/`repeat`/`for` rows; and the backward `goto` into a dead region.

**Negative controls are the half that matters here**, because this pass now
deletes more: a live infinite loop left by `break`, a live loop whose back edge
IS a goto, a **forward** goto over a return (survives only because a reachable
jump names it — the exact mirror of the row above it), nested loops with
`continue`/`break` and a `case`, and a `try`/`except` landing site. The C file's
output is diffed against **gcc -O2**, which prunes all of it and links without
the undefined symbols.

**Positive control, asserted rather than assumed:** the pinned pre-fix compiler
**fails both files** at load (`undefined symbol: NEVER_while` /
`PXX_NEVER_DEFINED_dlbe_while`). A guard that cannot fail prints PASS.

Shared-IR control-flow rewrite, so the one-backend fixedpoint is not evidence:
run on **x86-64, i386, aarch64, arm32, riscv32 and xtensa** (Pascal file, all
six identical; the C file on five — C-on-xtensa has no program entry stub at
all, pre-existing and unrelated). `-O1/-O2/-O3` identical; `-O0` still fails at
load, which is correct and is the open
`decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0`.

### One correction to the ticket

> `test/c_const_branch_dead_arm.c` already carries a goto row, added as a control
> against an over-eager fold

Not in that file — it has no `goto` at all. The control is `g1`/`Lrevive` in
**`test_const_branch_dead_arm.pas`**, and it is a **forward** goto to a live
label, which is the opposite hazard: it guards against deleting a reachable
region. The self-witnessing **backward** goto into a dead region was covered
nowhere, in either language, so both new files carry it. It is still true that
it falls out of the worklist for free and needed no case of its own.

Gate: fixedpoint converged; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-30 — resolved, commit f370bb085.
