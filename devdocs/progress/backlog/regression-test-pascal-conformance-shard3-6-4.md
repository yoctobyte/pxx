---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 3/6`. The job's own `src` (`tools/run_pascal_conformance.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard3/6 at cc03b4a51933 in step 1/1, `tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 3/6` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-17T16:27:08Z
- **Test source:** tools/run_pascal_conformance.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/run_pascal_conformance.sh`.
  ```
  tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --shard 3/6
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard3/6'` at cc03b4a51933a51b3e30c3334797c209f534504f

## Range
> **The named sha `cc03b4a51933` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cc03b4a51933`, last good `d0cad59b99e3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
o the ONLY thing holding this row is the `object` decision -- if that flips, this row is live and must be re-measured rather than assumed still blocked.
SKIP tobject7.pp — decided: old-style TP `object` types are not implemented (decide-old-style-object-types, option A, 28c19f214). NOT a gap to chase -- the decision's revisit trigger is a real program needing it, not a conformance row. Private nested type, typed const and static class property on top of the base feature.
SKIP tover4.pp — gap: 80-bit extended/cextended float type and overload resolution across single/double/extended
SKIP tpropdef.pp — wontfix: depends on FPC Classes/TComponent published-property RTTI streaming (stored/nodefault)
SKIP tstring3.pp — gap: THE CHAR HALF IS FIXED (2026-09-06, compiler 3fa98ccccf88) -- a one-character named const is a string initialiser now, so `FDivChars = (c1,c2)` and `FDIVStringS = (s1,s2)` compile; fixture test/test_a_one_character_named_constant_is_a_string_initialiser.pas. WHAT IS LEFT, line 15: a RESOURCESTRING as a typed-const array element (`= (RsFDivFlawed, RsFDivOK)`). Not the same gap and not a lookup miss: a resourcestring is deliberately NOT a constant here -- ParseConstSection routes it to DeclareInitialisedStringVar, i.e. real storage, which is what makes `@S` legal and is what FPC's runtime-replaceable resourcestring is. Its initial span IS recoverable (a PendingInit of Kind=1), but nothing marks the resulting sym AS a resourcestring -- isResStr is a parse-time parameter with no persistent flag -- so a rule keyed on "is a string var with a literal initialiser" would also admit `var s: string = 'x'; const A: shortstring = s;`, which fpc refuses. Needs a sym flag, i.e. a defs.inc slot (message frankH before taking one).
test-pascal-conformance: 69 pass, 1 fail, 13 skip, 9 auto-gated (of 92)
test-pascal-conformance: skips by tag: 5 gap, 3 wontfix, 4 decided, 1 accepts-invalid, 0 untagged/unknown
test-pascal-conformance: FAILURES: terecs4.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-22 — the borg watcher saw `test-pascal-conformance#shard3/6` GREEN at 6a75f7659fd6 (tier full) and did NOT close this: this is a repeat stub (`regression-test-pascal-conformance-shard3-6-4`, not `regression-test-pascal-conformance-shard3-6`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
