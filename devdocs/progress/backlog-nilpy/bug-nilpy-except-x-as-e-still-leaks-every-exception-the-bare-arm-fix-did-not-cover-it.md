---
prio: 55
track: N
type: bug
---

# `except X as e:` still leaks every exception object — the bound arm was never in the old repro

[[bug-nilpy-caught-exception-objects-are-never-freed]] is in `done/` and is
correctly done **for what it measured**. Its repro is `except ValueError:` —
the BARE shape. The BOUND shape, `except X as e:`, is the common one, was never
in the population being sampled, and still drops nothing.

## Measured (frankB, 2026-09-01, x86-64, `-dPXX_ALLOC_CENSUS`)

| shape | allocs | frees | live |
| --- | --- | --- | --- |
| `except Boom:` (bare, already fixed) | 4274 | 4272 | 2 |
| `except Boom as e:` | 4274 | **0** | **4274** |
| same, inside a `def` | 4274 | **0** | **4274** |

Not a late release the census misses: two 600-iteration calls plateau at
`live=3599` and STAY there while 8000 further allocations churn through, so
neither function RETURN dropped anything. The user cannot do it by hand either
— `e = None` and `del e` both still measure `frees=0`, because the store into
the binder is a **raw pointer store**, not a managed assign that would release
what it overwrites.

Verified pre-existing against `620989250~1` before any of this, since that
commit changed the adjacent condition.

## What I tried, why it is NOT the fix, and the repro that kills it

Creating the owning temp in all four cells (dropping the `NilPyUserCode` gate,
so the bound arm frees at handler exit like the bare one) **fixes the leak
completely** — `frees=4272, live=2` — and **corrupts `e.args`**:

```python
i = 0
while i < 3:
    try:
        raise ValueError(42)
    except ValueError as e:
        print(repr(e.args))
    i = i + 1
```

prints `(42,)` `()` `(42,)` — alternating, the signature of a block freed and
immediately reused. `str(e)` is unaffected; only `args` dies. Full-tier
`test-nilpy` catches it as `test_nilpy_exception_non_string_argument`
(`IndexError: list index out of range`), and `gate.sh quick` does NOT — quick
covers no NilPy at all.

So the object is **not rc=1 at handler exit**: something still borrows it, and
the constructor's reference is not ours alone to drop. That is the whole
question this ticket turns on, and it is why the bare-arm fix does not
generalise: with no binder there is no second holder.

The attempt is parked at `/tmp/.../ir.inc.nilpy-attempt` — do not restore it;
it is recorded so nobody re-derives it.

## HYPOTHESIS, not a finding — the shape a real fix probably has

Make the binder store **RETAIN** (rc 2), then release at handler exit (rc 1),
and let the existing rebind-release + scope-exit release drop the last one. The
binder would then genuinely own a reference instead of borrowing one, which is
what `feature-nilpy-object-reclamation` slice 4 assumes everywhere else. UNVERIFIED:
I did not confirm rebind-release actually fires on this symbol.

## A stale comment that is load-bearing, and worth fixing on its own

`PyClassSymArcEligible` (`compiler/symtab.inc`) says in its header:

> Except-handler binders are named and get their slot nil'd by the AN_TRY_EXCEPT lowering.

**They are not.** Dumped the IR rather than trusting it (`PXXDBG=a.ir:<proc>`):
the handler emits `exc_store` into the binder, the release call and `exc_clear`,
and **no store of 0 into the binder sym anywhere**. `exc_clear` zeroes the BSS
status globals (`BSS_EXC_OBJ/CLS/ADDR`), not the frame slot.

This matters beyond tidiness: the binder is a named `tyClass` local, so it IS
ARC-eligible, and `EmitManagedLocalCleanup` releases it at scope exit. Any fix
that frees the object at handler exit without nil'ing the slot arms a second
release on a freed pointer. Today the allocator has usually scrubbed the header
and the `PXX_OBJ_MAGIC` guard rejects it — luck, not correctness, and it stops
being luck once that block belongs to another object with a valid header.

Note the slot the lowering holds is the HIDDEN binder (`__py_exc<N>`), which
may not be the symbol the user's `e` resolves to — nil'ing the hidden one did
NOT prevent the corruption above. Whoever takes this should establish that
relationship first; it is probably the crux.

## Gate for this work

`gate.sh quick` is not sufficient — it covers no NilPy. Run
`PXX_ALLOW_FULL_SUITE=1 make test-nilpy` (~10 min); it is what caught the
corruption, and `test_nilpy_exception_non_string_argument` is the specific row.
