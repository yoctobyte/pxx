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
