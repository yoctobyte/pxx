---
prio: 45
track: T
type: bug
found: 2026-09-22
found-by: frankz-e5
blocked-by: []
summary: "test-aarch64#src:tools/compiler_srchash.sh is one of TSTATE.md's four open regressions and is the only one with NO ticket, so nothing can dispatch a seat to it. Red on borg since d36af549ea5b (last good 481fb6d72ba0, 1 commit in range: b965f8633 'feat(A): settle the aarch64 C-ABI gate by measurement'), and still red at pin v418's own binary. The visible failure tail mentions 'no working llvm-objdump (tried llvm-objdump-21, ...)', which would make this a missing HOST dependency rather than a compiler defect -- but the tail is truncated in the report and the fixedpoint line beside it reads 'verified', so WHICH of the two is the failing assertion is NOT established here. Filed as T because a missing toolchain binary is T's; RE-LANE TO A the moment someone shows the probe fails with llvm-objdump present."
---

# The aarch64 srchash job has been red since `d36af549ea5b` with no ticket

**Filed by the coordinator as a ROUTING gap, not as a diagnosis.** The finding is
that a tracked open regression has no ticket; the cause is somebody else's to
measure, and this ticket deliberately does not guess it.

## What is established

`devdocs/progress/tstate/TSTATE.md` lists four open regressions. Three have
auto-filed tickets. This one is named only inside `tstate/` state files —
`grep -rl 'test-aarch64#src:tools/compiler_srchash' devdocs/progress/` returns
`TSTATE.md`, `pin-shadow.log`, the two host `.json`s, the `runs-*.ndjson` and
report files, **and no ticket.** `ready`/`next` cannot surface it, so it has sat
for the whole bisect window with nobody able to be sent to it.

- bad `d36af549ea5b`, last good `481fb6d72ba0`, **1 commit in range**:
  `b965f8633 feat(A): settle the aarch64 C-ABI gate by measurement — it was already AAPCS`
  (`tools/whose_commit.sh` -> checkout `frankB`).
- Still `fail` in the newest full tier, `a8b9a3a55094`, 2026-09-22T12:37:02Z,
  `skips: 0`, `skip_holes: 0` — so it is failing, not being skipped.
- **That tier ran with `compiler_sha256: fda77c48b8ee`, which is pin v418's own
  binary.** This red is in the pin's grade.

## What is NOT established, and why this ticket stops here

The report's STILL-RED line is truncated:

```
self-host fixedpoint: verified — 1 round(s), fda77c48b8ee (stamp read back;
sources match it) | probe: no working llvm-objdump (tried llvm-objdump-21,
llvm-objd
```

Two statements joined, and the line is cut mid-word. **A missing `llvm-objdump`
on borg would make this a host-dependency red that should be a SKIP rather than a
RED** — the same shape as `bug-t-the-five-gtk-regressions-are-one-missing-host-
dependency`. But `verified` beside it is the STAMP path, which this fleet has
spent today learning to distrust, and I cannot tell from a truncated line which
of the two is the assertion that failed. **Run the repro before believing either
reading.**

```
tools/testmgr.py --tier full --job 'test-aarch64#src:tools/compiler_srchash.sh'
```

## The job's name is not the job's subject

The job is named for its SOURCE SET (`tools/compiler_srchash.sh`
`compiler/.pascal26.fixedpoint` +1), not for what it asserts, and **13 tickets in
`done/` plus 4 in `backlog/` carry `-compiler-srchash` in their slug from the same
naming rule.** Do not read that family as seventeen findings about the srchash
tool. It is a naming artefact and it is why this red looks like bookkeeping at a
glance.

## Ranking

p45 and stated rather than inherited: it blocks nothing known, it is one
cross-target job, and if it is a missing host binary the fix is an install or a
skip. **It re-ranks upward the moment someone shows the probe fails with
`llvm-objdump` present**, because then `b965f8633`'s aarch64 C-ABI gate is
unproven at the pinned compiler.
