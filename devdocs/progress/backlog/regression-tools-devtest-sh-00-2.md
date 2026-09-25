---
prio: 70
track: T
---

> **Track T from the job NAME `tools-devtest-sh`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`none`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest-sh#00 at 3b5e6becd38b in step 1/1, `n=0; bad=0; failed=''; \ : > /tmp/tools_devtest_sh_reds.log; \ for f in tools/*devtest*.sh; do \ case "$f" in \ *c_inte…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T05:12:25Z
- **Test source:** unknown (see repro commands)
- **Failing step:** line 1 of 1 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  n=0; bad=0; failed=''; \ : > /tmp/tools_devtest_sh_reds.log; \ for f in tools/*devtest*.sh; do \ case "$f" in \ *c_interop_devtest.sh|*tls_openssl_devtest.sh|*tls13_handshake_devtest.sh) continue ;; \ *truststore_devtest.sh|*tls_native_seam_devtest.sh) continue ;; \ esac; \ printf ' tools-devtest-sh
  ```

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest-sh#00'` at 3b5e6becd38bb9ddc27272cc1689193094d7c401

## Range
> **The named sha `3b5e6becd38b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3b5e6becd38b`, last good `a8c9f8659f8e`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
 pxx
case 3: POSITIVE CONTROL -- oracle emits unreadable asm (borg's branch)
  ok   exit 2 (instrument error)
  ok   does NOT say DISAGREEMENT
  ok   does NOT claim the green verdict
case 4: the three exits mean three different things
  ok   both instrument failures exit 2, never 1
case 5: disassembler NAMED but absent -- must not blame pxx
  ok   exit 2
  ok   names it an instrument failure
  ok   does NOT blame pxx
case 6: disassembler RUNS but is not a disassembler (/bin/true)
  ok   exit 2
  ok   does NOT say DISAGREEMENT
  ok   names the disassembler as the failing side

FAILED: 2 row(s)
  tools-devtest-sh: tools/devtest_selfhost_race.sh
  tools-devtest-sh: tools/file_ticket_clobber_devtest.sh
  tools-devtest-sh: tools/frozen_tree_guard_devtest.sh
  tools-devtest-sh: tools/selfhost_stamp_devtest.sh
  ---- the 1 failing script(s), repeated so the log TAIL names them
  FAIL: tools/aarch64_cabi_prologue_probe_devtest.sh
       Set LLVM_OBJDUMP=<path> or install llvm-objdump.
  FAIL real clang: no comparison line
       
  ok   real clang: a green means signatures were compared
case 2: POSITIVE CONTROL -- oracle emits nothing (false-GREEN branch)
  ok   exit 2 (instrument error)
  ok   verdict names it as unverified/instrument failure
  ok   does NOT claim the green verdict
  ok   does NOT blame pxx
case 3: POSITIVE CONTROL -- oracle emits unreadable asm (borg's branch)
  ok   exit 2 (instrument error)
  ok   does NOT say DISAGREEMENT
  ok   does NOT claim the green verdict
case 4: the three exits mean three different things
  ok   both instrument failures exit 2, never 1
case 5: disassembler NAMED but absent -- must not blame pxx
  ok   exit 2
  ok   names it an instrument failure
  ok   does NOT blame pxx
case 6: disassembler RUNS but is not a disassembler (/bin/true)
  ok   exit 2
  ok   does NOT say DISAGREEMENT
  ok   names the disassembler as the failing side

FAILED: 2 row(s)
  tools-devtest-sh: 4 green, 1 RED -- tools/aarch64_cabi_prologue_probe_devtest.sh

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-22 — the borg watcher saw `tools-devtest-sh#00` GREEN at 0f005c7b5597 (tier full) and did NOT close this: this is a repeat stub (`regression-tools-devtest-sh-00-2`, not `regression-tools-devtest-sh-00`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-24 — the borg watcher saw `tools-devtest-sh#00` GREEN at bf347a1e3b74 (tier full) and did NOT close this: this is a repeat stub (`regression-tools-devtest-sh-00-2`, not `regression-tools-devtest-sh-00`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-25 — the borg watcher saw `tools-devtest-sh#00` GREEN at fdca56b72841 (tier full) and did NOT close this: this is a repeat stub (`regression-tools-devtest-sh-00-2`, not `regression-tools-devtest-sh-00`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
