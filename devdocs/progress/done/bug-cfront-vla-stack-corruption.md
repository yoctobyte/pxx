---
track: C
prio: 65
type: bug
---

# C VLA (`int arr[n]` with runtime `n`) silently corrupts adjacent stack slots

Found 2026-07-29 while verifying doc claims for `docs/targets/c-frontend.md`
against `devdocs/progress/done/feature-c-vla-and-label-in-if.md` (marked
resolved, commit 2572fc82).

A runtime-sized local array compiles and *looks* fine for isolated indexed
writes/reads, but corrupts a sibling stack variable (the VLA's own bound, or a
loop counter declared after it) once the array is touched inside a loop.

## Repro

```c
#include <stdio.h>
int main(void) {
    int n = 5;
    int arr[n];
    int i;
    for (i = 0; i < n; i++) {
        arr[i] = i * i;
        printf("set arr[%d]=%d\n", i, arr[i]);
    }
    for (i = 0; i < n; i++) printf("get %d ", arr[i]);
    printf("\n");
    return 0;
}
```

Expected (and what gcc/CPython-reference C gives): five `set` lines, then
`get 0 1 4 9 16 `.

Actual pxx output:

```
set arr[0]=0
set arr[1]=1
get 0
```

Both loops exit after their second iteration (`i` effectively becomes `>= n`
too early), even though plain fixed-size arrays (`int arr[5]`) with the exact
same loop shape work correctly. This points at the VLA's dynamic-size stack
allocation overlapping `n`'s or `i`'s stack slot rather than a loop-codegen
bug in general.

Isolated writes without a loop (`arr[0]=10; arr[1]=20; arr[2]=30;` then one
printf) read back correctly — so the corruption is triggered by something in
the loop interaction (repeated indexed access and/or the loop-counter
increment), not by indexing itself.

## Impact

Silent wrong output, not a compile error or a crash — the dangerous kind. Any
C corpus using a runtime-sized local array (`char buf[len]`-style code is
common in real-world C) can silently misbehave under pxx today.

## Fixed 2026-07-30 — the silence, not the VLA

Root cause, one line: `CEvalConstPrimary` (cparser.inc) answers with the running
`Result` — 0 — for an identifier that is not `skConst`, and the dimension reader
had no way to tell that from a genuine zero. So `int arr[n]` was an array of
ZERO elements, overlapping whatever the frame put next; the loop counter was
that neighbour, which is why the loops "exited early" and why isolated writes
looked fine. Not a loop-codegen bug and not a re-evaluated size expression —
both hypotheses in the note below are wrong.

The evaluator now sets `CConstExprSawNonConst`, and the dimension reader refuses
with a named error. That converts a silent frame corruption into a diagnostic,
which is this ticket's subject; it does NOT implement VLAs, filed separately as
[[feature-c-vla-via-alloca]] with a worked-out design.

`00207.c` returns to `test/c-conformance/pxx.skip` tagged VLA — this ticket's
own predecessor sanctioned exactly that ("or re-tag skip as VLA-only"). It was
passing only because its `char test[argc]` is never meaningfully used: the pass
was luck on top of the corruption, not support.

## Suggested next step

Compare the VLA branch's stack-frame layout/offset allocation in
`compiler/cparser.inc` against the fixed-array path for the same loop shape;
check whether the VLA's runtime size expression is re-evaluated (and
re-clobbers a fixed offset) on each loop entry instead of once at declaration.

## Docs impact

`docs/targets/c-frontend.md` does NOT claim VLA support (deliberately, pending
this) — keep it that way until this is fixed and gated by a test.

## Log
- 2026-07-30 — resolved, commit 5f3e82811.
