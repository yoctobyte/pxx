---
slug: task-t-the-fifteen-reversed-rows-are-the-real-goal-1-backlog-not-the-emulator
track: T
prio: 60
type: task
status: rejected
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: 'A `full` tier IS green off borg as of 2026-09-22 (plexus, qemu 10.2.1, 4904 PASS / 0 FAIL / 0 FLAKY, 1283.7s, `d03add15c`) -- so the never-green record was never a statement about the tree, and the predecessor ticket `bug-t-native-s-red-is-one-row-and-full-s-is-ninety-four-...` is resolved. TWO THINGS STAND BETWEEN THAT AND GOAL 1''s "full green pin as release", and this ticket is both. (1) THAT GREEN IS NOT RELEASE-GRADE AND THE TIER SAYS SO ITSELF: 40 of its 46 skips are ABSENT CORPORA -- `library_candidates/c-testsuite` alone is 24 jobs, plus fpc-testsuite, fpc-rtl, lua, sqlite, cjson, fcl-json and `external/synapse` -- under a banner reading "A green verdict here does NOT cover them". Goal 1 wants skip_holes == 0, so the corpora have to be installed on whichever host publishes the release candidate before its verdict means what the goal needs; `tools/install_lib_candidates.sh` is the named route and it is itself one of the skipped jobs. (2) FIFTEEN JOB IDS ARE MATERIALLY MORE RED ON qemu 10.2.1 THAN ON 8.2.2 and they, not the emulator, are the remaining work: measured by `tools/tstate_toolchain_reversals.py` over native/full reports since 2026-09-04, `size-canary#src:tools/size_canary.py` 189/361 (52.4%) against 48/550 (8.7%), `test-fpjson#src:tools/install_lib_candidates.sh` 107/361 (29.6%) against 0/550, `test-core#src:test/test_libwriteln_parity.pas` 86/361 (23.8%) against 0/550, `test-emit-obj#src:test/test_emit_obj.pas@3` 65/361 (18.0%) against 0/550, three `lib-test#src:test/lib_synapse*.pas` rows 41/361 (11.4%) against 0/550, and eight more. THE HONEST STATUS OF THAT SECOND LIST IS THE POINT OF THE TICKET AND IT IS NOT "these rows are broken": host and toolchain are 1:1 across the whole archive window, so the reversed rates may be about the HOST (seven) rather than about the emulator, and the one direct control says they largely are -- of the eleven present in the plexus 10.2.1 full green, NINE RAN AND ALL NINE PASSED, which is ~13% likely if the rates transferred, ASSUMING INDEPENDENCE, and correlation within one run raises that, so it is a floor and evidence rather than proof. SO THE FIRST JOB HERE IS NOT FIXING FIFTEEN ROWS, IT IS DECIDING WHETHER THERE ARE FIFTEEN ROWS: re-run the reversals census after borg''s qemu moves (frankuser is carrying that escalation; it needs sudo on borg) and carry both rows rather than replacing, since a count whose ref was not recorded is unquotable rather than refuted. A row that stays red on borg AFTER the upgrade is real work in our own tree; one that clears is a fact about seven and should be struck from this list with the date. WHAT WOULD RETIRE THIS TICKET: a `full` tier with verdict GREEN and `skip_holes == 0` on any host. WHAT WOULD RETIRE ITS NUMBERS: any re-run at a different pinned ref, and specifically the post-upgrade census above.'
---

# The fifteen reversed rows are the real goal-1 backlog, not the emulator

This ticket exists because its predecessor answered its own question and the
answer moved the work somewhere else. **frankuser's framing, which is the
sentence to keep:** upgrading borg's emulator *"does not deliver a green tier —
it converts 'never green, and the verdict carries no information' into
'sometimes green, and a red means something'. The deliverable is INFORMATION,
not GREEN."*

## What is already established, so nobody re-derives it

- **`full` is green off borg**, measured, with the run's own qualification
  attached. See the predecessor's final section rather than re-running it.
- **`native`'s chronic row was an emulator version difference**, not compiler
  work: `test-core#src:test/c_crtl_wait.c` is red in 549 of 550 reports under
  qemu 8.2.2 and 0 of 361 under 10.2.1, from byte-identical compiler bytes.
- **Track B / crtl owns that row's `waitid` rusage path on riscv32** if anyone
  wants it fixed rather than routed around; it is not a tools ticket.

## The two jobs, in order

**1. Decide whether there are fifteen rows.** Re-run
`tools/tstate_toolchain_reversals.py` after borg's qemu moves. Strike every row
that clears, with the date; keep every row that stays red, because that one is
in our own tree. **Do not start fixing rows before this** — nine of the eleven
checkable ones already pass on a second 10.2.1 host, so some fraction of this
list is a fact about a retired machine.

**2. Install the corpora on the release-candidate host.** `skip_holes == 0` is
the goal-1 bar and a 40-job hole is not it. Note the recursion, which is worth a
grin and a check: **`tools/install_lib_candidates.sh` is itself one of the
skipped jobs**, so the tool that would close the hole is inside it.

## The trap, named in advance

**A row on this list that reddens after the upgrade will look like a new
regression**, because the upgrade and any compiler work will land in the same
week. The predecessor ticket pre-registers that expectation; read it before
attributing anything, and prefer
`git log -S'<the row>' -- <the skip or expected file>` over an inference from
timing.

## REJECTED WITHIN THE HOUR, BY ITS OWN AUTHOR'S NEXT MEASUREMENT — THE PREMISE IS FALSE

**`rejected/` and not `low-prio/`, because the report is WRONG rather than
unimportant:** there is no backlog of fifteen rows. Every one of the fourteen
reversed rows that had any reds **had already ENDED before seven's last
report** — none was red in its final 20 reports.

**Why the premise looked true.** I computed each row's red rate over a time
window and treated it as a **per-run probability**. It is not. Those reds are
single past **EPISODES**:

| row | reds | longest consecutive run | last red |
| --- | --- | --- | --- |
| `size_canary.py` | 189 | **158 in a row** | 2026-09-10 |
| `test_libwriteln_parity.pas` | 86 | **86 in a row**, one day | 2026-09-06 |
| `test_emit_obj.pas` | 65 | 13 | 2026-09-06 |

A row that is red for four days and then fixed reads as "52.4% red" over a
seven-day window, and 52.4% invites an inference about the next run that the
data cannot support. **So `P(all nine pass) ≈ 13%` was not a weak result, it was
a meaningless one** — there was no per-run probability for it to be about.

**AND THIS IS THE SECOND TIME TONIGHT THE SAME QUESTION WENT UNASKED.** frankuser
asked me hours earlier, of a different table, *"are the 16 greens CLUSTERED or
SPREAD?"*, and the answer dissolved a 2.6x I had published. I had the lesson in
hand, wrote a new table, and did not apply it. Promoted to the playbook for that
reason and not for the arithmetic.

**What survives and where it went:** the corpora half, to
`task-t-a-release-grade-full-green-needs-the-corpora-installed-skip-holes-is-forty`.
**What this changes for the owner escalation:** the predicted cost of upgrading
borg's qemu from these rows is **essentially zero**, so the trade earlier
reported has no cost side. frankuser guessed the cost would collapse; it
collapsed further than either of us measured, and for a different reason than
the one I checked.
