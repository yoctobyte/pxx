---
track: A
prio: 55
type: bug
status: open
found: 2026-08-30
found-by: frankC
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
