---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 2/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard2/6 at 64db7e73f8f1 in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 2/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-29T00:57:31Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 2/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard2/6'` at 64db7e73f8f1fd8f7070ca65beb3a4fc9561e5e6

## Range
> **The named sha `64db7e73f8f1` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `64db7e73f8f1`, last good `463383a0b19f`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
cal-management-operators-nested-and-array]] -- `a field of a record with a management operator is not managed yet`, line 81, measured 2026-09-06 at 88a0b3d93835. Its previous reason said "management operators across multiple record types", which is not what it stops on and named no ticket. Everything past line 81 is UNVERIFIED
SKIP toperator78.pp — gap: FPC refuses a binary operator overload only when the operation is ALREADY DEFINED for those operand types; pxx approximates that as "at least one operand is a record or class", and the gap is 91 of 209 measured same-type cells. The `**` half of this row now compiles (it gained a token, a precedence level, and an exemption from the aggregate rule); the wall is `operator >< (left, right: LongInt)` at line 9, which fpc accepts because `><` is predefined for SETS only -- NOT the `operator + (LongInt, AnsiString)` at line 14 that the diagnostic NAMES, because the refusal is raised after ParseSubroutine and reports the token past the previous declaration's body. Measured table and both halves of the fix in bug-p-the-operator-predefined-check-is-an-aggregate-approximation; tools/operator_predefined_matrix_probe.py regenerates it. %NORUN, so only the DECLARATIONS have to be accepted -- but a scalar-keyed overload is inert at the use site today, so the declaration half alone would burn this row by accepting operators that never fire
Segmentation fault
FAIL toperator94.pp — exit code 139 (want 0)
    TTest1 Implicit ShortString
    TTest2 Implicit ShortString
    timeout: the monitored command dumped core
SKIP tover3.pp — wontfix: dialect-pass — overload ambiguity — PXX deterministically ranks (picks longint for cardinal arg) by design; FPC-parity ambiguity errors belong to --strict-overload
test-pascal-conformance: 71 pass, 1 fail, 10 skip, 10 auto-gated (of 92)
test-pascal-conformance: skips by tag: 6 gap, 3 wontfix, 1 decided, 0 accepts-invalid, 0 untagged/unknown
test-pascal-conformance: FAILURES: toperator94.pp(exit=139)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
