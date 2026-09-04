---
track: N
prio: 40
type: bug
blocked-by: [bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate]
status: backlog
summary: "A NilPy `except V as e:` handler that binds X and is then unwound past by a DIFFERENT exception Y leaks X: 3.889 blocks per iteration, against 4.862 on pin v403 and a hypothetical ~0.9 if the pad released X. The unwind landing pad deliberately skips every handler binder, because it cannot tell X from an object that is IN FLIGHT (releasing that one is a use-after-free -- the SIGSEGV bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released fixed). The skip is the conservative half of a distinction the pad cannot currently make. STILL OPEN at cf8a5af93, which closed the sibling bound-arm leak; re-measured at 3.729/iteration. MEASURE IT WITH THE TRY INSIDE A FUNCTION -- a probe with the try in the module body now reads 0.000, because the sibling fix releases at re-execution of the try in the SAME frame, and that probe would read as fixed."
---

# A handler binder unwound past by a *different* exception still leaks

## What is conservative, and why it was made conservative

The unwind landing pad releases a frame's managed locals. A NilPy
`except V as e:` binder is a managed local and the pad skips it
unconditionally (`SymSkipScopeExitRelease`, `symtab.inc`), because on that path
the binder may hold the object currently IN FLIGHT — and releasing that is a
use-after-free, measured as a SIGSEGV.

But there are two cases and the pad cannot tell them apart:

| the handler | binder holds | releasing it is |
| --- | --- | --- |
| `raise` / `raise e` | the in-flight object | **a use-after-free** |
| `raise Other(..)`, or a callee raises | an object nothing else references | **correct, and the drop** |

Row two is skipped along with row one, so its object leaks.

## Measured 2026-09-04, `-dPXX_ALLOC_CENSUS`, slope N=2000 → N=8000

```python
def boom(k):    raise KeyError("k" + str(k))
def holder(k):
    try:                 raise ValueError("old" + str(k))
    except ValueError as e:  boom(k)
```
driven by an outer bare `except KeyError:` arm:

| binary | per iteration |
| --- | --- |
| pin v403 (no pad at all) | 4.862 |
| HEAD (pad, binder skipped) | **3.889** |
| a pad that released the binder | ~0.9, and it segfaults on a re-raise |

So HEAD is strictly better than the pin here and still ~3 blocks short of what
the pad could reclaim — the ValueError object plus the two blocks it owns.

## What a real fix looks like

Ask, at the pad, whether the slot holds the in-flight object, and release only
when it does not. The comparison is against `BSS_EXC_OBJ`. What makes it more
than a one-liner is that the release arm has **six copies** — `symtab.inc` for
x86-64 and five in `ir_codegen.inc` — so it is a compare-and-branch emitted six
times, and the reason it was not done under the SIGSEGV was time, not doubt.

An alternative worth costing first: a runtime `PXXObjReleaseUnwind(p, inflight)`
taking the in-flight pointer as a second argument, so the branch lives in
`builtinheap.pas` once and each backend only marshals one more register. That
trades six branch emissions for six argument setups, which may not be a win —
measure before choosing.

**Do not "fix" this by narrowing the skip to bare `raise` and `raise e`.** Both
were measured to crash and both are reachable, but so is any expression that
happens to evaluate to the bound object, and a syntactic test would pass every
probe anyone thinks to write while still crashing on the one nobody did.

## Not this

[[bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it]]
is the NORMAL path — 2.997 blocks per catch with no unwind involved at all, and
it is the bigger number. This ticket is only about the unwind path.

## Design banked (frankb-78, 2026-09-04) — measured again, and scoped

Re-measured at cf8a5af93, which closed the sibling
[[bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it]]:
**3.729 blocks/iteration, unchanged.** The pre-try release that fixed the
sibling cannot reach this — it fires on RE-EXECUTION of the try in the SAME
frame, and here the binder's frame is gone.

**Measure this with the try inside a FUNCTION.** A probe with the try in the
module body now reads 0.000, because the module body is one frame and the
pre-try release does reach it. That probe is the wrong shape for this ticket and
would read as fixed.

### What is actually wrong

`SymSkipScopeExitRelease` arm (2) is a COMPILE-TIME APPROXIMATION of a RUNTIME
property. The question the pad needs answered is "is this object the one
currently in flight" — the binder's reference is borrowed from the in-flight
exception and becomes its own only if the handler completes normally. The
predicate cannot see that, so it answers the strictly safer "a binder is never
released here", which is right for a re-raise and wrong for exactly this ticket.

Note the two failing populations are complementary, which is why one predicate
cannot serve both: releasing when it IS in flight is the SIGSEGV at 4edf60ff9;
not releasing when it is NOT is this leak.

### Option A (recommended, exact): runtime identity test in the pad

Release the binder unless it equals the in-flight object. That is the property
itself rather than a proxy, it is correct in both populations, and it DELETES
arm (2) — one mechanism replacing an approximation, not a second one beside it.

**Cost, and it is the reason this is banked and not done:** the pad's release
pass exists in SEVEN copies — `EmitManagedLocalCleanup` (symtab.inc, x86-64),
five arms in `EmitManagedLocalCleanupForTarget` (ir_codegen.inc), and
`WasmEmitManagedLocals`. Each needs the slot value and `BSS_EXC_OBJ` loaded into
two argument registers in its own idiom. There is no runtime-visible current
exception to shortcut this: `BSS_EXC_OBJ` is a compiler BSS slot and
`exceptions.pas` has no global for it (checked).

So this should follow, not precede,
[[bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate]] —
adding an eighth variation to a structure already ticketed as duplicated is the
wrong order.

### Option B (cheap, and INCOMPLETE — recorded so it is not re-derived)

Emit `PXXObjRetain(binder)` at a re-raise inside the handler (bare `raise;` or
`raise e`), then let the pad release binders UNCONDITIONALLY. Frontend-only, one
site, zero backend work, and the counts balance: construct 1, re-raise retain 2,
pad release 1, outer catcher frees 0; while the unwound-past case never retains,
so the pad's release is the drop this ticket wants.

**Why it is not the recommendation.** It is lexical. `except V as e: rethrow(e)`
where the callee does the raising emits no retain, the pad releases X while X is
in flight, and that is the 4edf60ff9 SIGSEGV back again — the same failure this
ticket's sibling predicate was written to prevent. A retain-on-any-escape
widening turns it back into two mechanisms for one concept.

Do NOT take a whole-protocol version of B (retain at EVERY raise, release at
handler entry): worked through and it breaks the re-raise chain — the outer
handler's entry release frees X before the outer handler runs.
