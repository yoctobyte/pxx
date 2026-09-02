---
prio: 70
track: A
owner: frankC
summary: "FIXED at 0ee41312d. `00213.c` on all five conformance targets: the dead-arm prune's label guard missed AN_CASE/AN_DEFAULT, so a `case` inside `if (0)` was pruned while AN_SWITCH's dispatch still jumped to it. Re-laned T -> A: the failing step named no owner and the fallback was wrong. NOTE FOR ANYONE READING THE MANIFEST: the conformance reds moved shard3 -> shard2 between two full runs, which is a DIFFERENT bug taking the same slot, not the old set shrinking — the two are indistinguishable on a dashboard."
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance#shard2/6 at 4a8f843f2ba5 in step 2/2, `tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T05:36:00Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_c_conformance.sh`.
  ```
  tools/run_c_conformance.sh ./compiler/pascal26 --shard 2/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance#shard2/6'` at 4a8f843f2ba55c41ff892867fa34d434d10f7a0b

## Range
> **The named sha `4a8f843f2ba5` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4a8f843f2ba5`, last good `fc388171aa43`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00213.c — compile error:
pascal26:156: error: invalid IR conditional jump target (label not defined)
(tail)
self-host fixedpoint: verified — 1 round(s), 8f5aa9306a71 (stamp read back; sources match it) --shard 2/6
FAIL 00213.c — compile error:
    pascal26:156: error: invalid IR conditional jump target (label not defined)
      near:       >>>  unit builtinheap 
test-c-conformance: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance: FAILURES: 00213.c(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-c-conformance#shard2/6` GREEN at 9037ea5d8471 (tier full) and did NOT close this: this is a repeat stub (`regression-test-c-conformance-shard2-6-2`, not `regression-test-c-conformance-shard2-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## Diagnosed and fixed (frankZ, plexus, 2026-09-02) — `0ee41312d`

Binary `ee1634a7195d8465`, reseeded from `stable_linux_amd64/default/pinned`,
`converged after 2 round(s)`, `gate.sh quick` GREEN with the FPC seed canary
live.

### The failure

```
pascal26: error: invalid IR conditional jump target (label not defined)
```

`00213.c`, one program, failing the same way on **all five** conformance
targets — native, aarch64, arm32, i386, riscv32. Five jobs, one cause. It was
green before (`37efd4565`).

### The cause

The dead-arm prune (`b8ee49996`) drops the body of a constant-false `if` or
`while`. Its escape guard `ASTSubtreeHasLabel` keeps any arm holding a label,
because a label is an entry point and the arm is only dead to a reader who
ignores it. The guard enumerated `AN_LABEL`, `AN_LABELADDR` and
`AN_GOTO_INDIRECT`, and missed `AN_CASE` and `AN_DEFAULT`:

```c
switch (i) { if (0) { case 41: printf("caseok\n"); } }
```

The arm went. `AN_SWITCH`'s dispatch is OUTSIDE the arm and still jumped to each
case's label, so the jump outlived its target. gcc prints `caseok`, and
`00213.c` exists precisely to test *"dead code inside if statements where there
are non-obvious ways of how the code is actually not dead due to reachable by
labels"* — its own header.

### The boundary — measured, six probes

| shape | |
|---|---|
| `case` at switch-body top level | ok |
| `case` in a bare `{ }` block | ok |
| `case` inside `if (1)` | ok |
| `case` inside `if (0)` | **FAILS** |
| `case` inside `while (0)` | **FAILS** |
| `default:` inside `if (0)` | **FAILS** (unconditional-jump path) |

**The discriminator is the PRUNING, not the nesting** — which is why the fix
belongs in the guard and not in the switch lowering. It fails at every `-O`
level including `-O0`, correctly: the prune is shared lowering, not an
optimisation.

### Fix and controls

`compiler/ast_arena.inc` — added the two kinds, plus a header paragraph saying
that `goto`, `&&label` and `case` are three spellings of one thing, so a guard
that enumerates spellings will keep missing the next one.

`test/c_dead_arm_holds_a_case_label.c`, wired into `test-core` because the
c-testsuite corpus is not in the quick tier — which is how this reached a full
tier with nobody's gate able to catch it. Positive control **both** ways: the
test does not compile on the pre-fix compiler, and a call to a symbol defined
nowhere inside `if (0)` still links silently, so the prune still FIRES and the
guard was widened rather than disabled. Rows 5 and 6 are that second control.
gcc returns 42 on the same file.

Shard 2/6 after: 37 pass / 0 fail / 0 skip native; 36 / 0 / 1 on each of i386,
aarch64, arm32, riscv32 (the skip is `00207.c`'s documented x86-64-only alloca).

### Corroborated independently the same day

frankC hit the identical missing enumeration from a second, unrelated pass —
pruning statements behind an unconditional transfer, wired into the `AN_BLOCK`
walk — where it made the compiler **reject its own crtl**
(`lib/crtl/src/stdio.c`, near `vsnprintf`). Two passes, one omission, one day.
The reachability decision now lives in `ASTSeqTailUnreachable` (ast_arena.inc),
called by both the `AN_SEQ` spine and the `AN_BLOCK` walk; it answers False for
anything that is not `AN_SEQ`, `AN_PAIR` included, deliberately — `AN_IF` uses
`AN_PAIR` for (then, else) and "everything after Left is unreachable" would
delete the else arm. Widen it THERE, not at a call site.

### Scope note

This is a NEW red — it postdates the set
[[umbrella-one-full-tier-run-with-no-red-tier]] was given, and the owner has
since said that umbrella is old reds only. It was fixed before that reached me;
the diagnosis is banked here rather than in a session's context, and the
umbrella is not claiming it.

## Verified at HEAD and closed (frankA, 2026-09-02)

`0ee41312d` is an ancestor of `origin/master` (`git merge-base --is-ancestor`,
not `cat-file -e`). The corpus is not installed on plexus, so `00213.c` itself
could not be run here — **what was run is the probe the fix added**, which is
the one that lives in the quick tier precisely because the corpus does not:

```
./compiler/pascal26 test/c_dead_arm_holds_a_case_label.c <out>   ->  ok
<out>                                                            ->  0, rc=42
```

`rc=42` is not a bare exit code here: `main` folds the eight per-row results
into a bitmask, prints it, and returns `f ? f : 42`, so 42 means every row
including both `if (1)` / bare-block controls agreed. The Makefile row asserting
only `$$?` is therefore asserting the output.

**Closed as fixed, not as green.** The distinction matters on this slug: the
ticket's own summary warns that the conformance reds moved shard3 -> shard2
between two full runs, so a green in this slot is not evidence about this
defect. What closes it is that the named cause was found, fixed, and carries a
test with a both-ways positive control — the test does not compile on the
pre-fix compiler, and a call to a symbol defined nowhere inside `if (0)` still
links silently, so the prune still FIRES and the guard was widened rather than
disabled.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d5574850f.
