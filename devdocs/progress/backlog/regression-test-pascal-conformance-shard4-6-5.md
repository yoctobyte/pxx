---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 4/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard4/6 at d11b8a1a99dd in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 4/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T06:35:44Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 4/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard4/6'` at d11b8a1a99dda7d388c66ecfa43889f89b7e9a58

## Range
bad `d11b8a1a99dd`, last good `562162b03a02`, 10 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tgenfunc3.pp — compile error:
pascal26:8: error: this token is not a class member: expected a field, method, property, a visibility section, var/class/type, or end
(tail)
`uses` compiles the second unit while the first one's operator is still pending. Cross-unit operators themselves WORK (controls in the ticket). bug-p-an-operator-declared-in-a-unit-interface-is-not-registered-until-its-body-is-parsed
SKIP tprocvar1.pp — decided: old-style TP `object` types are not implemented (decide-old-style-object-types, option A, 28c19f214). NOT a gap to chase -- the decision's revisit trigger is a real program needing it, not a conformance row. Named by that ticket as an acceptance test (same gap as tobject2.pp / tsealed6.pp). Its procvar content passes now — the previous reason named three gaps (method pointers, @Class.Method, typed-const procvars) and a fourth found chasing it (anonymous procedural types); all are fixed, and unskipping shows `object constructor init` is what is left.
SKIP tsealed6.pp — decided: old-style TP `object` types are not implemented (decide-old-style-object-types, option A, 28c19f214). NOT a gap to chase -- the decision's revisit trigger is a real program needing it, not a conformance row. Named by that ticket as an acceptance test; wants `object abstract` / `object sealed` on top of the base feature.
SKIP tstring4.pp — wontfix: reads ansistring refcount/length header words -- FPC internal string layout, which we do not claim. Re-measured 2026-09-06 at faa41e4b920f: it compiles (with the suite on the unit path) and runs. CORRECTION to the earlier note here, which said it "diverges only on GetFPCHeapStatus numbers" -- it does not. It also diverges on the Len header words (that IS this wontfix) AND on Str of Comp/Extended/Single. The Extended and Single rows are the decided Extended=Double architecture; the Comp row is a REAL defect hiding behind this skip and is now filed as bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting. wontfix stands; the reason did not.
test-pascal-conformance: 62 pass, 1 fail, 21 skip, 7 auto-gated (of 91)
test-pascal-conformance: FAILURES: tgenfunc3.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — the seven watcher saw `test-pascal-conformance#shard4/6` GREEN at c1961bc63ca0 (tier full) and did NOT close this: this is a repeat stub (`regression-test-pascal-conformance-shard4-6-5`, not `regression-test-pascal-conformance-shard4-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-06 — the seven watcher saw `test-pascal-conformance#shard4/6` GREEN at 4d26b9d07a70 (tier full) and did NOT close this: this is a repeat stub (`regression-test-pascal-conformance-shard4-6-5`, not `regression-test-pascal-conformance-shard4-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
