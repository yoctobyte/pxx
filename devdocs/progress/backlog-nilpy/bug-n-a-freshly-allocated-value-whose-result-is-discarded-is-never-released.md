---
type: bug
track: N
prio: 70
status: open
slug: bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released
---

# A call whose FRESH result is discarded never releases it -- methods and containers

`local.bump()` where `bump` returns a newly allocated object, with the result
dropped, leaks it. So does `panel_quad(...)` returning a fresh list. Binding the
same value, or passing it as an argument, is free.

Measured by lekkerzeilen-c8, 2026-09-15, at `375dcc647dd1` and `787d20032` --
i.e. AFTER the construction spelling was fixed in
`done/bug-n-a-construction-whose-value-is-discarded-is-never-released`:

| shape | | bytes/call |
|---|---|---|
| `local = local.bump()` | bound, fresh result | 0.11 |
| `h.q = h.q.bump()` | stored to an attribute | 0.10 |
| `local.bump()` | **discarded, FRESH result** | **80.10** |
| `local.same()` | discarded, returns `self` | 0.09 |
| `h.give()` | discarded, returns `self.q` | 0.09 |
| `mesh.update(panel_quad(...))` | fresh list as an ARGUMENT | 0.23 |
| `panel_quad(...)` | **discarded, FRESH list** | **328.23** |
| `note(12.3)` | discarded, fresh STRING | 0.87 |

## THE BOUNDARY IS NOT "FRESH" -- CORRECTED 2026-09-15, TWICE, AND IT IS STILL OPEN

The first version of this ticket said the boundary was freshness: that a
discarded call returning an EXISTING object (`self`, `self.q`) is clean because
it hands back a borrowed reference. **That was read off rows whose returned
object was a long-lived singleton**, where a leaked REFERENCE allocates nothing
and RSS cannot see it. Re-measured with the referent fresh per iteration, HEAD
`d5a02f0bd32c`, 12000 trips, CPython 0 on every row:

| row | | pxx | CPython |
|---|---|---|---|
| `h = H()` | baseline | 0 | 0 |
| `h = H(); h.num()` | discards an INT | **0** | 0 |
| `h = H(); h.me()` | discards `self` | **120** | 0 |
| `h = H(); h.give()` | discards `self.q` | **72** | 0 |
| `h = H(); h.fresh()` | discards a FRESH object | **72** | 0 |
| `h = H(); k = h.me()` | BINDS `self` | **0** | 0 |

So a discarded CLASS result leaks whichever of the three it is, an `int` result
does not, and binding the same value is clean. `num` and `me_bound` are the
controls that pin it to the discarded class result rather than to method calls
in general.

## AND THEN THE OBVIOUS FIX REFUTED THE OWNERSHIP MODEL THAT TABLE IMPLIES

If every one of those results arrives owning +1 -- which is what
`IRNodeOwnsFreshCallResult` and `IRNodeYieldsOwnedRef` both assert, and what the
leaks look like -- then releasing it once per call is exactly right. It is not.
**Two attempts, both SIGSEGV, both parked as patches, neither landed:**

1. **`IRDropManagedResult`, a `tyClass` arm storing the result into a hidden
   ARC-eligible local** (the same treatment the `tyAnsiString` arm beside it
   already gets). Does not crash, and fixes the discarded-LIST row (328 -> 0
   bytes/call), but leaves the method rows untouched. Reason: rebind-release is
   emitted by the AN_ASSIGN lowering, NOT by `IR_STORE_SYM`, so a raw store into
   a temp drops nothing on the way past -- in a 12000-trip loop it frees exactly
   the last object. Patch: `$SCRATCH/ir_dropmanaged_class_arm.patch`.
2. **The same arm releasing immediately** (`PXXObjRelease` on a `tyPointer`
   spill), which is also what CPython does. **SIGSEGV.** Narrowing it to
   `ResolveNodeRec(astNode) >= REC_UCLASS_BASE` -- user classes only, excluding
   every pylib/Pascal callee -- **still SIGSEGV**. Patch:
   `$SCRATCH/ir_dropmanaged_class_arm_gated.patch`.

Attempt 2 is the informative one: if `me()` and `give()` returned +1, one
release per call could not over-release. **They leak AND they cannot be
released, so the ownership model above is wrong and nobody has established what
the real one is.** That is the open question this ticket now carries, and it
must be answered with an objtrace retain/release census per shape -- not from
the RSS numbers, which have already misled twice.

**THE CRASH LANDS NOWHERE NEAR THE CAUSE** and cost an hour: it surfaced inside
`rss_kb()`'s `return` line, releasing a reused heap block, in a file where every
single row passed IN ISOLATION and only crashed together. If you attempt this,
expect that shape and do not trust a per-row green.

Strings remain a real boundary and a working one: a discarded fresh string does
NOT leak, so AnsiString ownership is already correct and widening a rule to
cover it would be an error in a third position.

## WHERE THE FIX BELONGS, AND WHAT TO ESTABLISH FIRST

`IRDropManagedResult` (`compiler/ir.inc:1304`) is the right hook and it already
does this job for `tyAnsiString` and for dyn arrays: the AN_SEQ spine calls it
on every statement's value. It needs a `tyClass` arm.

Two things to fix in it regardless of which arm is chosen, both measured:

* Its return-type fallback reads `Procs[ASTIVal[astNode]].RetType` only when
  `ASTKind[astNode] = AN_CALL`. **A method is `AN_VIRTUAL_CALL`**, so for the
  commonest discarded shape there is the type stays `tyUnknown` and every arm is
  skipped. Both carry the proc index in IVal.
* A `tyClass` temp must not be the ARC-eligible kind unless something also emits
  the rebind-release -- see refuted attempt 1.

**BEFORE WRITING THE ARM, SETTLE OWNERSHIP WITH objtrace**, per shape: does a
NilPy method returning `self`, returning `self.q`, and returning a fresh object
each emit a retain on the way out? The RSS table says all three leak; the
release experiment says at least one of them is not owned. Those cannot both be
true and no fix is safe until one of them is retracted.

**And whatever lands must cover CONTAINERS.** A discarded list costs 328 bytes
against 72-120 for a small class -- a whole backing buffer, not an 8-byte
reference -- so the container case is the expensive half, and attempt 1 already
showed it is separable from the method case.

## NOT A LEKKERZEILEN FIX, AND THAT WAS CHECKED RATHER THAN ASSUMED

Every discarded call on a hot path in the demo returns None, a bool, or an
existing attribute: `self.rig.update(dt)` (no return), `self.traffic.update(...)`
(no return), `self.boat.step(...)` (returns an existing object),
`self.rig_data()` (existing), `sail.raise_lower(dt)` (bool). Rank this on the
language, not on that demo.

(c8 withdrew a 137-site census of this that resolved "does this callee return a
value" BY METHOD NAME across the package, so one `update` returning something
marked every `update` in every class. The five above were checked individually.)
