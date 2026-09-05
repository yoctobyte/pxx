---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 5/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 17 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard5/6 at 6e00f29b0d93 in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 5/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T22:19:46Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 5/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard5/6'` at 6e00f29b0d93c1de28a173ae8867c7f08dd0b3e3

## Range
> **The named sha `6e00f29b0d93` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6e00f29b0d93`, last good `a5814f2780de`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tdefault8.pp — compile error:
pascal26:24: error: unknown type: TRange
pascal26:28: error: unknown type: TRange
(tail)
eric syntax + nested record/pointer types inside a generic class
SKIP tgeneric91.pp — gap: Self in class procedure of a generic class specialized cross-unit
SKIP tgeneric97.pp — wontfix: expects FPC's internal specialized ClassName 'ttest<system.longint>'
SKIP tgenfunc12.pp — gap: the generic-method halves parse now (incl. the `<T: class>` constraint); what is left is `.Free` on a generic method RESULT and a free `specialize F<C>;` with no argument list
SKIP tgenfunc18.pp — wontfix: dialect-pass — same as tgenfunc17, and carries the same re-measure-on-fix caveat.
SKIP tmoperator7.pp — gap: management operators (Initialize/Finalize) inside object/dynarray of records — the `class var` half landed 2026-09-05 and the row now stops at `undefined variable (InitializeCount)`, which is the management-operator cluster, not this one
SKIP toperator6.pp — gap: COMPILES AND RUNS, and exits 2 -- a silent wrong answer, not a refusal, so do not read this row's skip as a parse gap. `value := high(int64)+100` must select the QWord `operator :=` overload and selects the Int64 one. Constant typing plus conversion-overload ranking
SKIP toperator91.pp — gap: the duplicate-conversion check keys on the result type KIND, so String[80], String[90] and ShortString are one result type and the second Explicit/Implicit declaration is refused. FPC treats the capacities as distinct -- same tk inconsistency toperator93 exposed at the use site
SKIP tprocvar2.pp — gap: typed const procvar initialized with bare proc name (TP mode), procvar via move()
SKIP tsetsize.pp — wontfix: asserts FPC's exact set-size/packing layout (SizeOf(set of subrange))
SKIP tstring10.pp — gap: punicodechar/pwidechar value casts + unicodestring/widestring conversions (Flush/Output landed)
SKIP tstring5.pp — gap: RTL `ExitCode` variable missing (needed by testsuite erroru unit); ansistring compares
test-pascal-conformance: 59 pass, 1 fail, 24 skip, 7 auto-gated (of 91)
test-pascal-conformance: FAILURES: tdefault8.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
