---
prio: 55
track: N
type: bug
summary: "`except X as e:` leaks 3 heap blocks per caught exception -- the exception object and two it owns. Re-measured 2026-09-04 at 938d9d9dbbe6: bare `except X:` is 0.000, bound is 2.997, and it is 2.997 whether the handler USES `e` or not, so the leak is in the BINDING and not in anything done with it. Unchanged by the unwind-landing-pad fix (bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released), which is a different path: the frame here is not unwound past, the handler is in it. The obvious fix corrupts `e.args` -- see below."
status: done
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

## CORRECTED: the nil DOES happen — my instrument could not see it

I originally recorded here that except-handler binders are never nil'd, on the
strength of a `PXXDBG=a.ir` dump showing no store of 0 into the binder sym.
**That conclusion was wrong, and the way it was wrong is the useful part.**

frankA found the mechanism (fixed the comment in `fa2249f8b`): the nil is
emitted by the NilPy **watermark pass** at the head of each statement in
`ir_codegen.inc` (`PyZeroedProc` / `PyZeroedUpTo` -> `EmitZeroFrameSlot`), whose
own comment names handler binders explicitly. It emits at **CODEGEN, not as
IR** — so `a.ir` cannot observe it, and looking there returns a truthful "no
such store" about a question the instrument does not answer. Absence of
evidence read as evidence of absence, from a tool that was working correctly.

`PyClassSymArcEligible`'s header was genuinely stale in other respects (it
claims only NAMED locals are eligible while the `Result` two lines below has no
name filter, and a second comment inside the same function contradicts the
first) — but not in the way this section originally said.

**THE HAZARD BELOW IS UNAFFECTED, and is why this section stays.** Nil-at-
statement-head does not prevent it: the binder is ARC-eligible,
`EmitManagedLocalCleanup` releases it at scope exit, and a release added at
handler exit is a SECOND release of the same pointer. Only nil'ing at the
handler-exit release closes that. Today the stale pointer's header has usually
been scrubbed by the allocator and the `PXX_OBJ_MAGIC` guard rejects it — luck,
not correctness, and it stops being luck once that block belongs to another
object with a valid header.

So: whatever fix lands here must nil the slot AT the handler-exit release, not
rely on the statement-head pass.

## Gate for this work

`gate.sh quick` is not sufficient — it covers no NilPy. Run
`PXX_ALLOW_FULL_SUITE=1 make test-nilpy` (~10 min); it is what caught the
corruption, and `test_nilpy_exception_non_string_argument` is the specific row.

## Re-measured 2026-09-04 (frankb-78), binary `938d9d9dbbe6`

Slope of live blocks between N=2000 and N=8000, `-dPXX_ALLOC_CENSUS`:

| arm | per raise |
| --- | --- |
| `except ValueError:` (bare) | 0.000 |
| `except ValueError as e:` — handler reads `str(e)` | **2.997** |
| `except ValueError as e:` — handler never mentions `e` | **2.997** |

**The third row is the one that is new, and it narrows the fix.** An unused
binder leaks exactly as much as a used one, so nothing the handler does with `e`
is involved: the retain that is never balanced happens at the BIND. A fix that
reasons about uses of `e` is aimed at the wrong statement.

Three blocks is the exception object plus the two it owns. `allocs` is identical
across all three rows (31686 at N=8000) — the same work, only the frees differ.

Re-measured deliberately after
[[bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released]] landed, in
case that pad covered this too. It does not, and the reason is structural rather
than incidental: the pad releases the locals of a frame an exception unwinds
PAST, and this handler is in the frame that CATCHES. Different path, still open.

## Fixed — and this ticket's recorded reason for NOT fixing it was wrong

The fall-through free in `AN_TRY_EXCEPT` is emitted under
`if (not NilPyUserCode) or (ASTSOffset[handlerNode] < 0)` — Pascal always, NilPy
only when the arm is BARE. That is the whole hole, exactly as the body says.

The fix is a release at the pre-try `IR_DEFAULT_MEM` nil, which already runs on
every execution of the try: release-then-nil rather than nil-over-the-top. By
the time control is back at the statement head the previous handler has
completed normally — a re-raise leaves through the exception path and never
returns there — so the object is nobody's but ours. Measured: `allocs` identical
at 19780 for 3000 catches, `frees` 7842 → 19778, `live` 11938 → 2.

**THE `e.args` CORRUPTION THIS TICKET BLAMED ON THE FIX CLASS IS A SEPARATE,
OLDER BUG, AND IT IS PRESENT IN PIN v403.** `Exception.GetArgs` had MIXED
OWNERSHIP: it returned the stored `argsv` BORROWED, while its other arm returns
a freshly built tuple OWNED. The caller's protocol for a property result is one
owned reference per read — it stores into a managed temp, releasing what that
temp held before, and never retains — so every read was one release too many.

That was invisible for as long as a caught NilPy exception was never freed:
nothing else ever released `argsv`, so the surplus release merely drained a
leaked block and *looked like cleanup*. Freeing the exception makes its finalize
release `argsv` too, and the two collide.

The instruments, in the order they separated it:
- `-dPXX_OBJTRACE` — zero `R` lines anywhere, so nothing ever retains; the
  release of iteration N's tuple fires during iteration N+1's read.
- `-dPXX_HEAP_DEBUG` — names it outright, `RELEASE of a FREED object`, and
  quarantine suppresses the symptom, so the output is clean while the fault
  prints.
- the pin, run with the same probe — **it does the identical stale release**.
  It just never aliases a live block, because it frees nothing else.

So the alternating `(42,) () (42,)` is a freed-and-reused tuple, not a wrong
args computation, and "this fix class corrupts `e.args`" was an attribution
error: the fix class exposes a bug it did not cause. A control that only
compares against the pin cannot see it — the pin passes.

`args` is the only `read Get...` property in pylib, so there is no sibling of
this shape to fix alongside it.

Residual, unchanged and still open:
[[bug-nilpy-a-handler-binder-unwound-past-by-a-different-exception-still-leaks]]
— measured again here at 3.729 blocks/iteration with the try in a FUNCTION
(fresh frame per iteration). The pre-try release cannot reach that: it fires on
re-execution of the try in the SAME frame, and the unwound-past binder's frame
is gone. A probe with the try in the module body reads 0.000 and is the wrong
shape for that ticket.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit cf8a5af93.
