---
summary: "test_nilpy_operator_dunder_missing_fail still expects a COMPILE error; the missing-dunder case now raises a runtime TypeError like CPython, so the assertion is stale"
type: bug
track: N
prio: 55
---

# The missing-dunder expect-FAIL assertion is stale (second instance)

- **Type:** bug — stale test assertion (Track N, `.npy` tests)
- **Found:** 2026-08-01 by Track T, in the first run of the newly enrolled
  `test-nilpy` tier ([[bug-t-xeon-job-set-covers-only-a-third-of-nilpy-tests]]).

## The assertion

`Makefile`, inside `test-nilpy`:

```make
# a class with no matching dunder used to silently compute garbage instead of erroring
! ./$(COMPILER) test/test_nilpy_operator_dunder_missing_fail.npy /tmp/... > /tmp/...log 2>&1
grep -q "class has no __add__" /tmp/...log
```

It demands the **compile** fail with `class has no __add__`.

## What actually happens now

```
$ ./compiler/pascal26 test/test_nilpy_operator_dunder_missing_fail.npy /tmp/nod26
ok: /tmp/nod26 [...]                                  # compile rc=0
$ /tmp/nod26
Unhandled exception: TypeError: unsupported operand type(s) for this operator
$ echo $?
1
```

So the diagnostic **moved from compile time to run time**, and the runtime form
is a proper catchable `TypeError` — which is what CPython does for
`NoOp() + NoOp()`. The new behaviour is *more* correct, not less: the original
bug this test guards (`bug-nilpy-arithmetic-operator-dunders-not-dispatched`,
"silently compute garbage on the raw class handles") is still fixed. Nothing
regressed. Only the assertion is out of date.

The positive half of the same recipe passes:

```
(5, 8) / (3, 4) / (12, 18) / (2.0, 3.0)      # matches expectation exactly
```

## This is the second instance of one pattern

`bug-t-xeon-job-set-covers-only-a-third-of-nilpy-tests` records the first:
`b1f5b0e0b` moved `[1,2] + "x"` from a compile error to a catchable runtime
`TypeError`, invalidating an expect-compile-failure assertion, which was fixed
separately. This is the same semantic shift reaching a second test that was
never fixed — because `test-nilpy` was outside the watcher's job set, so nobody
saw it.

Worth sweeping the other `!`-prefixed `_fail.npy` assertions in the same pass:
any that expect a *compile* diagnostic for something NilPy now defers to a
runtime `TypeError` is stale by the same argument.

## Fix

Assert the runtime behaviour instead of the compile failure:

```make
./$(COMPILER) test/test_nilpy_operator_dunder_missing_fail.npy /tmp/nod26
! /tmp/nod26 > /tmp/nod.log 2>&1
grep -q "TypeError" /tmp/nod.log
```

That keeps the guard the test exists for — the operator must not silently
compute garbage — while matching where the diagnostic now lives.

## 2026-08-02 — already FIXED by `784613a31`; verified and resolving

Filed by Track T from the newly-enrolled `test-nilpy` tier at almost the same
time I hit the same red from the other direction (triaging T's two NEW-REDs).
`784613a31` — *"fix(N): update the missing-dunder assertion to the
runtime-TypeError behaviour"* — is this ticket's fix; the two crossed.

Verified rather than assumed, through make's own expanded recipe
(`make -n test-nilpy | grep nodunder_fail26 | bash -e`): PASSES. The assertion
now reads

```make
./$(COMPILER) test/test_nilpy_operator_dunder_missing_fail.npy /tmp/test_nilpy_nodunder_fail26
test "$$(/tmp/test_nilpy_nodunder_fail26)" = "$$(printf '%b' 'caught missing __add__\nstill running')"
```

and the program prints exactly that — it compiles, raises a catchable runtime
`TypeError`, the handler runs, execution continues. Which is CPython's own
behaviour and what this ticket asked for.

No further code change. Recording the duplication so the pattern is visible:
this is the SECOND stale expect-FAIL assertion from the same cause (the first
was `test_nilpy_list_plus_nonlist_fail`, `eeae1e4a3`). Both were left behind by
the deliberate move of missing-operator cases from compile errors to catchable
runtime TypeErrors. If a third turns up, the fix is to grep the recipe for
remaining `! ./$(COMPILER)` expect-FAIL lines and check each against current
behaviour, rather than waiting for them to surface one at a time.

## Log
- 2026-08-02 — resolved, commit 784613a31.

### The sweep, actually run

Rather than leave that as advice: the three remaining `! ./$(COMPILER)`
expect-FAIL assertions in `test-nilpy` were extracted and executed via make's
own expansion. **All three still valid.** They are a different family — genuine
compile-time failures that are not moving to runtime:

- `--no-shims` with a dotted import (a missing shim IS a build-time error)
- inconsistent dedent (syntax)
- mixed indent (syntax)

So the stale-assertion family is now closed at two instances, not open-ended.
