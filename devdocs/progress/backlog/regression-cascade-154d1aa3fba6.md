---
prio: 70
---

> **origin/master has advanced 17 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 18 jobs newly red in e417731e9..154d1aa3f (12 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 18 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-29T16:51:37Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `154d1aa3fba6` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `154d1aa3fba6`, last good `e417731e9007`, **12 commit(s) in range** (12 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `b3fd1c76065d` Merge branch 'master' of github.com:yoctobyte/pxx
- `53f17676d27d` merge(rust): Track R rungs 1-7 — Option<T>, record ABI, engine idioms
- `f431211f2fb2` Merge remote-tracking branch 'origin/master' into rust
- `fcfe1cba1013` feat(rust): the engine's own idioms compile — chess.rs shapes end to end
- `c59aab128dd4` merge: master@7290327d6 into the rust topic branch
- `557df36d5e34` feat(rust): aggregate literals in return position, and implicit tail returns
- `e4cbaf85d93d` fix(rust): `&`/`&mut` parameters must alias the caller
- `1ede0ffad3d7` feat(rust): fixed-array struct fields (`squares: [i64; 64]`)
- `68dac6d2a9d3` feat(rust): expression scrutinees, `if let`, unwrap_or
- `2efff6df5138` feat(rust): Option<T> (and records) through fn signatures and returns
- `f20746561006` merge: master@4213b4b76 into the rust topic branch
- `8fb3f776cd3b` feat(rust): Option<T> as a monomorphized generic enum (stage-2 rung)

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 154d1aa3fba6c0500271d12a8578158dc04975a7

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `lib-test#src:test/lib_inttohex.pas@2`
- `lib-test#src:test/test_dynlib.pas`
- `test-aarch64#src:test/test_cdecl_indirect.pas`
- `test-aarch64#src:test/test_extern_c.pas`
- `test-aarch64#src:test/test_extern_c_float.pas`
- `test-aarch64#src:test/test_parallel_reduction.pas`
- `test-arm32#src:test/test_cdecl_indirect.pas`
- `test-arm32#src:test/test_extern_c.pas`
- `test-arm32#src:test/test_extern_c_float.pas`
- `test-emit-obj#src:test/cxtensa_obj.c@1`
- `test-i386#src:test/test_cdecl_indirect.pas`
- `test-i386#src:test/test_extern_c.pas`
- `test-i386#src:test/test_extern_c_float.pas`
- `test-nilpy#src:examples/tk/tkinter_facade.npy`
- `test-nilpy#src:test/test_nilpy_parent_call_after_instantiation.npy`
- `test-nilpy#src:test/test_nilpy_startswith_tuple.npy`
- `test-sqlite-threads-aarch64#src:compiler/.pascal26.fixedpoint`
- `tools-devtest#00`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

---

## TRIAGE, 2026-08-29 — NOT A CODE REGRESSION. All 18 are host or pre-existing.

**Do not bisect the Range section.** Every buildable commit in it is a Track R
commit, which is the most incriminating possible framing and it is wrong. The
lane it accuses measured it first (frank-rust) and the coordinator confirmed the
load-bearing half from a source the claimant did not choose.

**Cause: `seven` is missing the 32-bit and cross runtimes that plexus has.** Its
baseline `e417731e9007` was the box's own first-ever sweep, so a capability the
host never had reads as a capability that just broke.

| # | jobs | verdict |
| --- | --- | --- |
| 9 | `test_extern_c`, `test_extern_c_float`, `test_cdecl_indirect` on i386 + arm32 + aarch64 | **host**: no target loader. All nine produce **empty** actual output — three unrelated backends emitting nothing at all in one sweep is the programs not running, not codegen. |
| 1 | `lib-test#test_dynlib` | **host**, and it names the cause out loud: `qemu-i386: Could not open '/lib/ld-linux.so.2': No such file or directory`. |
| 1 | `lib-test#lib_inttohex` | **host/tooling**: Python traceback inside `/home/seven/trackt-watch/tools/reportlab_diff.py`. |
| 1 | `test-aarch64#test_parallel_reduction` | **host**: marked TIMED OUT. |
| 2 | `test-nilpy#…tkinter_facade.npy`, `test-sqlite-threads-aarch64#…` | **host, pending packages** — `tcl-dev`/`tk-dev` and `libsqlite3-dev` are on the owner's install list for this box. Lower confidence than the rows above: the sqlite job's key is a fixedpoint target, so it may be a build failure rather than a missing library. Re-check after provisioning. |
| 4 | `tools-devtest#00`, `test-emit-obj#cxtensa_obj.c`, `test_nilpy_parent_call_after_instantiation`, `test_nilpy_startswith_tuple` | **pre-existing**, each with its own earlier `bad=` sha. Folded into the cascade, not newly red. |

**Counter-evidence run at HEAD** (frank-rust, `1625a25ba841`, self-hosted binary
`5ee03822ce0b`, converged after 1 round) — all six of the reproducible cross jobs
**PASS** on this box: i386, arm32 and aarch64 × `extern_c` and `cdecl_indirect`.

**Coordinator's independent confirmation:** `/lib/ld-linux.so.2` exists on plexus
(symlink to `i386-linux-gnu/ld-linux.so.2`, dated 22 Jul); `seven.json` carries
the `Could not open` string for the dynlib job. The two arms do not share an
upstream — one is this box's filesystem, one is seven's own report.

**Also on seven, same provisioning gap from other angles:** `fpc is not on PATH`,
no uforth tree, and the `opt` tier has never completed a run.

### The filing defect this exposes — for Track T's tooling, not for this ticket

**The stub carries the incriminating half of the evidence and omits the
exculpating half.** The Range section — machine-derived, precise, authoritative
in tone — lists twelve Rust commits. The *reasons* (`Could not open`, `TIMED
OUT`, a Python traceback) live only in the tstate JSON and appear nowhere in the
ticket a human opens. A reader who trusted the range and did not go fetch the
report would have spent an afternoon bisecting Rust commits for a missing
loader, and nothing in the ticket would have contradicted them.

This is not a bad range computation; the range is correct and its own caveat
("the named sha CANNOT be the cause") is correct too. The defect is that **two
fields of one report disagree and the lower-status field is the one that is
right** — and the layout gives no hint that the reasons outrank the range.

**Remedy for the cascade filer: put each red job's failure REASON next to its
name in the stub.** A cascade whose reasons are visible is triaged by reading;
one whose reasons are a fetch away is triaged by bisection. New face of the
generator family (index: `feature-a-a-refusal-is-a-claim-with-a-date-on-it`).

**Status:** not a Track R item, not p70 code work. Blocked on provisioning
`seven` (owner's box, owner's installs). Re-sweep after provisioning and re-file
whatever is still red — expected: the four pre-existing regressions and nothing
else.
