---
type: bug
track: N
prio: 45
status: open
slug: bug-n-a-variant-call-result-that-returns-a-fresh-object-is-retained-by-the-caller
summary: A Variant-returning pylib call whose result is a NEWLY BUILT object (pyvar_slice, pyvar_add on lists) leaks it once per evaluation when the receiver is a variant -- the object leaves the callee owned (+1) and the caller retains it again, assigned or not. Present in pin v428.
---

# A fresh object returned through a Variant is retained by the caller too

Measured 2026-09-25 (frankH), `-dPXX_OBJTRACE`, pin v428 and HEAD alike:

    v = [1, 2, 3]
    if len(v) > 5:
        v = None          # makes v a VARIANT local
    print(len(v[0:2]))    # slice: A 1, R 2, never released

`x = v[0:2]; x = None` ends at rc 1, and `x = v + [4]` at rc 2. The typed
receiver (`buf[1:3]` on a class-typed local) is clean, so the leak is in the
variant-result route.

NOT a callee fix: releasing inside `pyvar_slice` after `Result := ...` gives
`r 0, F` and then `R 1` on the FREED block, a use-after-free. The callee's
+1 is the right answer, and the caller's extra retain is the leak.

What it costs beyond memory: `memoryview` (TPyBytes.FViewOf) could not keep
CPython's "no resize while exported" guard, because a view sliced through a
variant never returned its export. Add that guard back once this is fixed.

## Closed 2026-10-03 (frankuser): flat at HEAD, no fix of its own

Re-measured at 13fcd29da1 (x86-64, -dPXX_ALLOC_CENSUS, `live=` from the
census header, not the size histogram, which counts allocations, not live
blocks). Every shape this ticket names is now flat, 100 against 5000
passes:

- discarded call results: `h.num()`, `h.me()`, `h.give()`, `h.fresh()`,
  `h.bump()`, `h.bump().fresh()`, a fresh list, a fresh str: live 14-20,
  no growth.
- results read only for truth: `if re.match(..)`, `if s.split(..)`,
  `if re.findall(..)`, `while f() and ..`, `or`, `not`, a conditional
  expression: live 16-28, no growth.
- slice and concat through a variant receiver (`v[0:2]`, `x = v[0:2];
  x = None`, `v + [4]`, `if v[1:]`): live 17 -> 18.
- eval() of a list, dict, set, tuple, range, `.encode()`, `.to_bytes()`:
  live 22-33, no growth.

Nothing landed for this ticket by name. The ownership work of 2026-09-15 to
2026-10-03 (owned call results, the discard binder, the position-0 spill)
closed it on the way. What keeps it closed is
test_nilpy_a_discarded_or_variant_routed_result_is_released, which has one
arm per ticket of the four closed together: HEAP_DEBUG diff against
CPython, census bound 300 at 5000 passes (live 90) with a keep control
that trips, and i386.

**Follow-up NOT done:** the memoryview "no resize while exported" guard this
ticket says to restore (TPyBytes.FViewOf) has not been put back. It is now
unblocked; it was out of scope for a leak re-measurement.
