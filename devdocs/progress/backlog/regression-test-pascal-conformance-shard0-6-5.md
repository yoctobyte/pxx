---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 19 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard0/6 at ef03a6282980 in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:53:02Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 0/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard0/6'` at ef03a6282980142702466c3688817b7bd90f738e

## Range
> **The named sha `ef03a6282980` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ef03a6282980`, last good `3b13f585f5f4`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ting from specialize of another generic
SKIP tgeneric21.pp — gap: accepts-invalid — nested generic-in-generic declaration — semantics unverified, real gap (see bug-pascal-missing-diagnostics-fail-tests triage 2026-07-11)
FAIL tgenfunc13.pp — %FAIL test compiled (must be rejected)
SKIP tgenfunc19.pp — gap: generic global function + class helper method resolution via specialize
SKIP tgenfunc5.pp — wontfix: parses and runs since the generic-method work; the ROW calls an instance method on a never-Created object and pxx raises nil-reference 216 where fpc runs it. Pre-existing and unrelated to generics (an ordinary non-generic method on a nil receiver does the same on pin v403). Adding one `t := TTest.Create` makes it exit 0.
SKIP tinterface4.pp — wontfix: needs FPC's `variants` unit and FPC's IInterface/NewInstance refcount internals
SKIP tmoperator2.pp — gap: record Initialize/Finalize management operators with managed fields
SKIP tmoperator8.pp — gap: management operators AddRef/Copy/Initialize/Finalize on records
SKIP tover1.pp — gap: `widestring` is an ALIAS of `ansistring` unless {$define PXX_WIDE_PAYLOAD}, so its two string overloads are one type declared twice. PASSES under that define (measured 2026-09-05) — the overload key itself now carries the element WIDTH. Retiring the gate is chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload
SKIP tprocvar3.pp — gap: delphi-mode procvar of object, @-less proc assignment, codepointer method addresses
SKIP tstring11.pp — gap: an open `array of WideChar` / `array of AnsiChar` argument binding a UnicodeString/RawByteString parameter. The overload KEY is no longer the blocker — under {$define PXX_WIDE_PAYLOAD} the two Test1 candidates are distinct and the refusal moves to the open-array conversion at line 42; without it they are one type (same alias gate as tover1)
test-pascal-conformance: 67 pass, 1 fail, 19 skip, 5 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenfunc13.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
