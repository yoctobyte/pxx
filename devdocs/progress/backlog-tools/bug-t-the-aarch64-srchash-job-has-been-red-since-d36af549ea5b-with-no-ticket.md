---
prio: 45
track: T
type: bug
found: 2026-09-22
found-by: frankz-e5
blocked-by: []
summary: "test-aarch64#src:tools/compiler_srchash.sh is one of TSTATE.md's four open regressions and is the only one with NO ticket, so nothing can dispatch a seat to it. Red on borg since d36af549ea5b (last good 481fb6d72ba0, 1 commit in range: b965f8633 'feat(A): settle the aarch64 C-ABI gate by measurement'), and still red at pin v418's own binary. The visible failure tail mentions 'no working llvm-objdump (tried llvm-objdump-21, ...)', which would make this a missing HOST dependency rather than a compiler defect -- and that IS now established (frankb-8e, 2026-09-22): it is the missing host dependency, and the 'verified' fixedpoint line beside it is the PASSING half that the truncation joined to it. Three measurements, not a reading of the tail: tools/aarch64_cabi_prologue_probe.sh exits 2 on a missing objdump BY DESIGN and prints exactly that text, saying in its own words that it is an INSTRUMENT failure and not a statement about pxx; b965f8633 changed ZERO files under compiler/ or lib/ so it cannot have moved a fixedpoint; and with llvm-objdump-21 present the probe PASSES -- exit 0, 5 signatures agreeing with clang, 2 stack-passed skips. THAT DISCHARGES THIS TICKET'S OWN RE-LANE CONDITION IN THE NEGATIVE (it says re-lane to A if the probe fails WITH llvm-objdump present; it passes), so it STAYS T. THE EXIT 2 IS NOT THE BUG AND MUST NOT BE MADE A SKIP -- the script records that exit 0 was considered and rejected as laundering, citing done/bug-t-tstate-launders-skip-into-pass, and an earlier version of this gate that only checked the name was non-empty printed a FABRICATED 'DISAGREEMENT -- 5 pxx-side broken'. RESIDUAL, with an owner: borg needs llvm-objdump installed (a host change), or the harness should report exit 2 as INSTRUMENT-UNAVAILABLE distinctly from a finding at exit 1 -- a T harness change, the better fix because it generalises, and the script already separates the codes while nothing downstream reads the distinction. Filed as T because a missing toolchain binary is T's; RE-LANE TO A the moment someone shows the probe fails with llvm-objdump present."
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

## 2026-09-22 (frankb-8e) — which assertion fails IS established, and it is the objdump gate

`b965f8633` is mine (authored in this checkout, confirmed by
`tools/whose_commit.sh`), so this is my row to settle. **It is the missing host
dependency, not the fixedpoint**, and T is the right lane.

Three things settle it, none of them a reading of the truncated tail:

1. **The probe exits 2 on a missing objdump, by design and in those words.**
   `tools/aarch64_cabi_prologue_probe.sh` gates `llvm-objdump-21` then
   `llvm-objdump`, requires the tool to RUN rather than merely be named, and on
   failure prints exactly the text the report shows — `probe: no working
   llvm-objdump (tried llvm-objdump-21, llvm-objdump)` — followed by *"This is
   an INSTRUMENT failure and is NOT a statement about pxx."*
2. **`b965f8633` changed no compiler code at all.** Zero files under
   `compiler/` or `lib/`: a Makefile row, the probe script, the playbook, the
   board and two tickets. It cannot have moved a fixedpoint.
3. **With a working objdump the probe passes.** Run here at `fda77c48b8ee`,
   clang 21.1.8, `llvm-objdump-21` present (plain `llvm-objdump` ABSENT, which
   is why the fallback exists): **exit 0, 5 signatures agree with clang, 2
   skipped (stack-passed).**

So the `self-host fixedpoint: verified` line beside it in the report is the
PASSING half, and the truncation is what joined the two into one ambiguous row.
**This also discharges this ticket's own re-lane condition in the negative** —
it says re-lane to A the moment someone shows the probe fails with
llvm-objdump present, and the measurement shows it PASSING with it present.
Stays T.

**THE EXIT 2 IS NOT A BUG AND MUST NOT BE "FIXED" BY MAKING IT SKIP.** The
script's own comment records that exiting 0 here was considered and rejected,
citing `done/bug-t-tstate-launders-skip-into-pass`: an ABSENT clang is a
declared host limitation and skips, while a present-but-unusable instrument is
an undiagnosed condition, and exiting 0 would launder it into a pass. An
earlier version of this very gate tested `[ -n "$OBJDUMP" ]`, which
`LLVM_OBJDUMP=/nonexistent/...` satisfies, and it printed
`verdict: DISAGREEMENT -- 5 pxx-side broken` — a fabricated compiler defect. So
the loud red is the design working.

**THE RESIDUAL, WITH AN OWNER, because "not a pxx defect" is half a finding.**
borg has no working `llvm-objdump` and this job will stay red there until that
changes. Two candidate remedies, and I am doing neither unilaterally: install
`llvm-objdump` on borg (a host change, not mine — needs whoever owns that box),
or teach the harness to report a nonzero exit **2** as INSTRUMENT-UNAVAILABLE
distinctly from a finding at exit 1, which is a Track T harness change and a
better fix because it generalises past this one probe. The script already
separates the two exit codes for exactly this purpose and nothing downstream
reads the distinction. **Do not reach for a third option that makes the row
quiet.**
