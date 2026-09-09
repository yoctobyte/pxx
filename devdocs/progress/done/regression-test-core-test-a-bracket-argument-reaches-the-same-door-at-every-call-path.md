---
slug: regression-test-core-test-a-bracket-argument-reaches-the-same-door-at-every-call-path
title: "The constructor bracket door found a differently-NAMED constructor and parsed the argument with the wrong stride"
track: P
prio: 70
type: regression
status: done
found: 2026-09-09
found-by: twatch
owner: frankS
blocked-by: []
summary: "FIXED 2026-09-09. Caused by 231ac5795 (mine): ClassCtorArraySigAt scans every constructor of the class regardless of NAME, which was harmless while first-match ran and became a wrong PARSE the moment `array of const` started winning the slot. `TC.Create([10, 20, 30])` against `constructor Create(const A: array of Integer)` found `CreateV(const A: array of const)` further down the same class and built a TVarRec vector the Integer body read with an Integer stride -- sum 10 against fpc's 60, which is the exact defect this fixture was written to catch on 2026-09-06, reintroduced through the other half of the same predicate. `Create` and `CreateV` are two NAMES, not two overloads, and fpc's array-of-const preference is between OVERLOADS; the routine is scoped to the called name now, with a parent-chain walk so an inherited `Create` is still found. Confirmed independently three ways before I touched it (frankH): pin v399 green, frankH's tree with its own in-flight extraction stashed and rebuilt still RED, and this ticket. FOUND BY THE FULL TIER AND NOT BY QUICK -- `gate.sh quick` was GREEN on the same tree, which is the whole argument for Track T sampling the tip."
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 15 is `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"`. The job's own `src` (`test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas at af0e5a0ad099 in step 2/15, `tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T14:40:10Z
- **Test source:** test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas tools/expect_same.sh
- **Failing step:** line 2 of 15 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_bracketdoor26 "$(/tmp/test_bracketdoor26 | tail -n 2)" "$(printf 'fails=0\nBRACKETDOOR OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas'` at af0e5a0ad09916b0563d12739a9410322bbc7611

## Range
> **The named sha `af0e5a0ad099` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `af0e5a0ad099`, last good `15de9cd799fd`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2533959/test_bracketdoor26  [code=339736B  data=35120B  bss=88452B  procs=881]
expect_same: MISMATCH [test_bracketdoor26]
--- expected
+++ actual
@@ -1,2 +1,2 @@
-fails=0
-BRACKETDOOR OK
+FAIL constructor, open array of scalar: got 10 want 60
+fails=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution, 2026-09-09 (frankS)

`compiler/pasparser_call.inc` — `ClassCtorArraySigAt` takes the constructor
NAME and matches on it (`UMemberNameMatch`), walking the parent chain so an
inherited `Create` is still reachable; without that walk the name restriction
would lose the inherited case the class-wide scan used to cover by accident.
`compiler/pasparser_expr.inc` — the ctor name is captured before the three
`Next` calls eat it.

### Why quick could not see it

`gate.sh quick` was GREEN on the tree that shipped this. The row lives in
`test-core`, which the full tier runs and quick samples past. Both frankH's
stash-and-rebuild control and Track T's `61f1fbb39` NEW-RED at `af0e5a0ad099`
reached it independently, and the pin (v399) was green — three readings that
fail differently, which is why the attribution to `231ac5795` did not need a
bisect.

### The guard now lives in the fixture that introduced the rule

`test/test_p_an_array_of_const_wins_a_bracket_argument.pas` gained `TCNamed`
and `TCNamedVrFirst` — a class with `Create(array of Integer)` beside
`CreateV(array of const)`, in BOTH declaration orders, each asserting `sum=60`.
Both orders on purpose: the arrangement that actually broke had `Create`
declared FIRST and the class-wide scan reached past it anyway, so a single-order
row would have passed while the bug was live. The bodies sum rather than count,
because a count is the same number for an Integer vector and a TVarRec one.
