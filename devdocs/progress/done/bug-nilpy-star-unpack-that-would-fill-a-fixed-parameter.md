---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`g(*xs)` where `g` declares fixed parameters BEFORE its `*args` is refused: the split between those parameters and the packed tuple depends on len(xs), a run-time fact the compile-time packing cannot answer. Loud and self-naming, but CPython accepts it."
status: done
owner: claude-A-N
---

# `*unpacking` that would fill a fixed parameter

```python
def g(x, *rest):
    return x, rest

print(g(*[9, 8, 7]))     # CPython (9, (8, 7))
                         # pxx: "Nil Python: *unpacking that would fill a fixed
                         #       parameter of a collecting callee is not
                         #       supported yet (the split depends on the
                         #       operand's length)"
```

Split out of [[bug-nilpy-star-unpack-into-a-star-args-callee]] when the splice
landed (2026-08-15). The written-argument form `g(1, *xs)` works — only an
operand that has to REACH BACK over a fixed slot is refused.

## Why it is not the same fix

The splice that solved the sibling is a compile-time `extend`: every element
goes into the packed tuple. Here the first `len(xs) >= 1` elements belong to
`x` instead, and which they are is unknowable until the call runs.
`g(*[], 3)` binds x = 3; `g(*[9], 3)` binds x = 9 and rest = (3,) — the same
source, a different shape per operand.

## The shape a fix probably takes

Run-time distribution, and the pieces exist: `x := xs[0]` is a list getitem and
`rest := xs[1:]` a slice, both already lowerable. Bounded to the case where the
splice is the LAST positional (otherwise a written argument after it also
lands at a position nobody can compute); beyond that, an arity dispatch like
`PyStarForwardCall`'s.

A short operand must raise CPython's TypeError ("missing 1 required positional
argument"), not read past the end.

## Gate

`.npy` diffed against CPython: `g(*xs)` for operands shorter than, equal to and
longer than the fixed parameters; two fixed parameters; a fixed parameter with
a DEFAULT before the star; and the too-short case raising TypeError.

## RESOLVED — distributed at run time, as the ticket predicted

The ticket's "shape a fix probably takes" was right, and the pieces were all
already there. `PyPackStarArgs`'s splice arm now handles `pos < si` instead of
refusing it:

1. The operand is materialised into ONE hidden TPyList temp (via the existing
   `PyStarOperandAsList`, so a str spreads its characters and a variant is
   converted rather than cast). Once — `g(*f())` calls `f` once however many
   slots it feeds, which the test asserts with a call counter.
2. `pystar_check_min` (new, pylib) raises before anything reads past the end,
   with CPython's exact wording including the missing parameters' names —
   `g() missing 1 required positional argument: 'x'`,
   `h() missing 2 required positional arguments: 'a' and 'b'`. The names travel
   as one `'|'`-separated literal, so the frontend does the naming and the
   runtime only picks the missing tail.
3. One positional per fixed slot the operand reaches: `pystar_arg(xs, k)`. A
   slot **with a default** takes the default when the operand ran out — `k(*[9])`
   on `def k(x, y=2, *rest)` is `(9, 2, ())` — which is a per-slot run-time test,
   the same `pystar_has`/ternary pair the forwarded-call desugaring uses.
   (`pystar_has1` is the positional-only half of `pystar_has`: the reach-back has
   no kwargs dict to pass, and synthesising a nil class argument as an AST literal
   is exactly the kind of hand-built node that goes wrong quietly.)
4. The tail — `pylist_slice(xs, si - start, MaxInt)`, clamped by `PySliceBounds`
   — extends the packed tuple.

**Bounded, deliberately, to a splice that is the LAST positional.** A written
argument after it would land at a position that depends on the operand's length,
which is the same unanswerable question one level up; that now gets its own
message instead of the old blanket one.

**Verified** byte-identical to CPython over 14 rows: the ticket's example, an
operand exactly filling the fixed slots with nothing left for the tuple, longer
and shorter operands, two and three fixed parameters, a str operand, a defaulted
parameter before the star at three lengths, all three too-short TypeErrors with
their exact messages, the written-argument form unchanged, and the
single-evaluation counter. Rows added to
`test/test_nilpy_star_unpack_into_a_collecting_callee.npy` — the sibling
ticket's own file — with its `.expected` regenerated. `tools/gate.sh quick`
GREEN.

**Filed separately, NOT folded in:**
[[bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it]] — found because
the first draft of the test appended helpers named `g`/`h`/`k`/`m`, and the file
already had a `g`. The EXISTING rows above then printed kilobytes of raw memory,
because NilPy bound that earlier call to the LATER `g`, whose return type is a
tuple where the caller expected a str. Reproduced on `pinned`. The test's
helpers are now `rb1`..`rb4`; the underlying defect is a real silent wrong value
and has its own ticket at prio 35.

## Log
- 2026-08-15 — resolved, commit 101a3465f.
