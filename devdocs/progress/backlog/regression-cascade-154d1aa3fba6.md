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

## TRIAGE 2026-08-29, host `seven` (the host that filed it) — NOT A CODE REGRESSION

**Do not chase the twelve Rust commits listed under Range.** None of them is the
cause of any job in this cascade. The auto-filing is working exactly as designed
— it says up front that it "looked at neither the build, the box nor the range"
— and this is the triage it asked for.

`seven` joined as a watcher box today and this was its FIRST completed full tier.
The cascade is dominated by **host provisioning that the deploy contract does not
cover**, and the deciding evidence is in the job logs, not in the range:

```
qemu-i386:    Could not open '/lib/ld-linux.so.2':        No such file or directory
qemu-aarch64: Could not open '/lib/ld-linux-aarch64.so.1': No such file or directory
```

`tools/run_target.sh` says it plainly: dynamically linked PXX binaries (the
external-C-call tests) need the guest `ld.so` + libc, via `QEMU_LD_PREFIX`
pointing at a sysroot that **`tools/install_cross_sysroot.sh` provisions and that
nothing in the deploy path ever runs.** So the tests did not fail; they never ran.

| # | jobs | cause | status |
|---|---|---|---|
| 10 | `test-{i386,arm32,aarch64}#{test_cdecl_indirect,test_extern_c,test_extern_c_float}` + `lib-test#test_dynlib` | no cross sysroot; no i386 loader | **provisioned** — `install_cross_sysroot.sh` (aarch64, arm32) + `libc6-i386` (`/lib/ld-linux.so.2`). Awaiting the next full tier to confirm. |
| 3 | `test-nilpy#{parent_call_after_instantiation,startswith_tuple}`, `test-emit-obj#cxtensa_obj.c` | **pre-existing, already ticketed from plexus** — `regression-test-nilpy-test-nilpy-parent-call-after-instantiation`, `regression-test-nilpy-test-nilpy-startswith-tuple`, `regression-test-emit-obj-cxtensa-obj` | duplicates. They read as NEW here only because `seven` had no full-tier baseline; a first run on a host has nothing to diff against. |
| 3 | `test-aarch64#test_parallel_reduction` (240.4s / 240s), `tools-devtest#00` (90.1s / 90s), `test-sqlite-threads-aarch64` (126.8s) | **duration signals, landing within 0.4% of their budgets.** `seven` is a dual Xeon E5645 (2010, 2.4 GHz, no AVX) — materially slower per core than plexus, so class budgets calibrated there are near-unachievable here. Per track-t.md a timeout is not a statement about the tree and is not bisectable. | needs per-box budget review, not a bisect |
| 1 | `test-nilpy#tkinter_facade` | tcl/tk absent | packages installed; awaiting confirmation |
| 1 | `lib-test#lib_inttohex` | not yet isolated | open |

**So: 0 of 18 are attributable to the range, and at most 1 is an untriaged code
question.** Fourteen were the box, three were already known.

### The finding worth keeping, which is not about these jobs

A watcher box provisioned strictly per `devdocs/dev/track-t.md`'s "Deploy a
watcher box" comes up **able to report and unable to measure**, and the two are
indistinguishable from the outside. `trackt setup --fetch-corpus` covers
`library_candidates/` only. It does not run, mention, or check:

- `tools/install_externals.sh` → `external/synapse` (this is the same tree whose
  two-month coverage hole track-t.md's own *"which numbers have never changed?"*
  section is written about — it was still absent here today)
- `tools/install_cross_sysroot.sh` → the qemu guest runtimes above
- the uforth tree (13 jobs; the SKIP line carries the exact clone command)

The corpus gaps SKIP, which at least announces itself. **The sysroot gap goes
RED**, and a red is read as a defect in the tree — which is how a fresh box's
first report became a 18-job accusation against twelve innocent Rust commits.
All of the above are now provisioned on `seven`. Filed separately as a Track T
defect in the deploy contract; this ticket should close once the next full tier
confirms the ten.

*(Triaged by the Track T agent on `seven` under the provenance rule: this box's
run produced the finding, so this box triages it.)*

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
