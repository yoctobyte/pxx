---
summary: "Commit the fpjson/fpcunit suite harness (203/203) as a repo target — today it lives only in volatile /tmp staging"
type: feature
prio: 50
---

# fpjson + fpcunit suite as a committed, enrollable test target

- **Type:** feature (Track B — library testing; enrollment afterwards is
  Track T, see [[task-t-enroll-pascal-conformance-tier]] siblings)
- **Status:** backlog
- **Opened:** 2026-07-14

## The problem

The fcl-json test suite — **203/203 GREEN** as of b318–b327
([[project_fpjson_suite_green_b318_b327]]), running FPC's real `fpjson.pp`
under a real `fpcunit` console runner — is the strongest OOP/RTL exerciser
pxx has ever passed: classes, virtual class methods, metaclass Self, is/as,
exceptions, overloads, TStringList surface, float Str() formatting. And it
exists ONLY as `/tmp/fpjson-stage/` (239 files, volatile, uncommitted). A
reboot deletes it; a regression in any of the b318–b327 fixes is invisible.
fpcunit itself (the runner) has the same status.

## Scope

1. **Staging, reproducible:** extend `tools/install_lib_candidates.sh` with an
   `fcl-json` target that fetches `packages/fcl-json/src` +
   `packages/fcl-json/tests` + `packages/fcl-fpcunit/src` (and the few
   fcl-base deps the stage needed) from the same pinned FPC commit the
   testsuite fetch uses (`$FPC_URL` / `$FPC_COMMIT`), into
   `library_candidates/fcl-json/`. Record license note in PROVENANCE.md
   (FPC RTL/packages: LGPL with static-linking exception).
2. **Reconstruct the harness** from `/tmp/fpjson-stage` while it still exists
   (compare against the fetched upstream to extract any local patches — the
   stage predates some fixes; ideally zero patches remain now).
3. **Make target** `test-fpjson`: build the consoletestrunner suite with
   `$(PXX_STABLE)` (`--mimic-fpc`), run it, assert `203` passes / `0`
   failures in the output. Wire into `make lib-test` or standalone.
4. Hand to Track T for tier enrollment once green as a target.

## Why prio 50

User call 2026-07-14: external-library testing ("the nice testing stuff" —
Pascal scripting, fpjson, fpcunit) is the current Track B focus; this is the
already-green suite with zero regression protection, so it comes before new
corpus rungs.

## Done when

Fresh clone + `install_lib_candidates.sh fcl-json` + `make test-fpjson` =
203/203, no /tmp state involved; a regression in the fpjson/fpcunit chain
turns the target red.
