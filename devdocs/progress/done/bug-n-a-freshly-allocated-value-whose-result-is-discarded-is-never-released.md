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

## THE OBVIOUS FIX CRASHED, AND I READ THAT AS REFUTING OWNERSHIP. IT DOES NOT -- SETTLED 2026-09-15

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

I read attempt 2 as informative: if `me()` and `give()` returned +1, one release
per call could not over-release, so a crash had to mean they were not owned.
**That inference is the thing to retract.** A crash proves the PATCH is wrong,
never that the model is -- and this patch had two independent defects (below),
either of which releases an object nobody handed it.

**THE objtrace CENSUS THIS TICKET ASKED FOR, RUN 2026-09-15 AT `d5a02f0bd32c`,
the verified fixedpoint of `922cefa3a`.** `-dPXX_OBJTRACE`, one call per shape,
no loop -- `A <addr> <rc> <size>` on alloc, `R <addr> <rc>` on retain:

```
--- base      A 0x...020 rc=1 size=16     (H)
              A 0x...050 rc=1 size=16     (Q, as h.q)
--- me        R 0x...020 rc=2             -> never released
--- give      R 0x...050 rc=2             -> never released
--- fresh     A 0x...080 rc=1 size=16     -> never released
--- end
```

**All three discarded class results arrive owning +1**, and none is released.
`me()` and `give()` each emit a RETAIN on the way out (1 -> 2) and `fresh()`
arrives at rc=1 from its own allocation. So the RSS table above stands, the
model `IRNodeOwnsFreshCallResult` and `IRNodeYieldsOwnedRef` both assert is
correct, and one release per discarded call is the right shape after all.
**There is no borrowed case among these three.** Nothing here is open.

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

**OWNERSHIP IS SETTLED -- see the objtrace census above.** The arm is written
and the class half is FIXED; what follows is the record of what was actually
wrong, because both "defects" this ticket listed on 2026-09-15 were themselves
wrong and a later reader would otherwise chase them.

**RETRACTED -- neither of these was the problem.** Both came from one earlier
probe run, and that probe ran against a `compiler/pascal26` that was not the
fixedpoint of its own sources (see the instrument note at the end):

* *"`ResolveNodeRec` answers the stale constant 52"* -- **52 is not stale, it is
  `TPyList`'s recId.** The rows reaching the site were dominated by pylist
  internals, so a true answer repeated on every row read as a constant. The
  value was correct throughout.
* *"`ASTKind` is 8 on every row, never 32"* -- **flatly false.** A probe at the
  site prints `astkind=32` for the discarded method call, exactly as the AST
  dump shows. The method call reaches `IRDropManagedResult` and always did.

**WHAT WAS ACTUALLY WRONG, AND IT IS ONE THING: THERE WAS NO `tyClass` ARM.**
The type is already resolved at that site -- `IRTk[irNode]` is `Ord(tyClass)`
for a discarded method call (`irkind=30`, `IR_VIRTUAL_CALL`) -- so the
`AN_CALL`-only return-type fallback never mattered for this shape either. The
function simply fell through to `NodeDynDepth` and exited.

**AND THE GATE IS THE CALLEE'S PROVENANCE. Three weaker gates were tried; all
three fail, and the first two are what produced every SIGSEGV:**

| gate | why it fails |
|---|---|
| `PyProgramMode` alone | a whole-COMPILATION flag. `lib/rtl`'s Pascal units compile in the same run, so it separates nothing. **SIGSEGV** |
| `ProcRetRecId >= REC_UCLASS_BASE` | `TPyList`'s recId is 52, so every pylist site passes it. **SIGSEGV** |
| `ProcUnitIdx = -1` | right for a def in the main `.npy`, wrong for every IMPORTED NilPy module (measured: `unitidx=669`). Silently skips multi-module programs, which is all the real ones |

The crash is `TPyList.append_self` and `pylist_mark_tuple` -- Pascal methods
returning their own receiver as a chaining convenience, **borrowed**, with no
retain to balance. `re.pas` discards 27 such results, and releasing them
free-lists a live object; the SIGSEGV then surfaces far away, inside `rss_kb()`,
on the reused block.

`UnitIsPyModule` (symtab.inc) is the RECORDED fact and is the gate that works.
`PyModUnitIdx`'s own comment in `defs.inc` says it exists because *"the routine
lives in another unit"* was being used as a proxy for *"Pascal library facade"*
-- the identical mistake, one ticket earlier.

**And whatever lands must cover CONTAINERS.** A discarded list costs 328 bytes
against 72-120 for a small class -- a whole backing buffer, not an 8-byte
reference -- so the container case is the expensive half, and attempt 1 already
showed it is separable from the method case.

## WHAT THE LANDED ARM FIXES, AND THE ONE ROW IT DOES NOT

Measured on the committed repro at the arm's own compiler, CPython 0 on every
row:

| row | | before | after |
|---|---|---|---|
| `h = H()` | baseline | 0 | 0 |
| `h.num()` | discards an INT | 0 | 0 |
| `h.me()` | discards `self` | 120 | **0** |
| `h.give()` | discards `self.q` | 72 | **72 -- UNFIXED** |
| `h.fresh()` | discards a FRESH object | 72 | **0** |
| `k = h.me()` | BINDS `self` | 0 | 0 |

**`give` is a DIFFERENT CARRIER, not a missed case, and that is why it never
appeared as a candidate at the site.** From the AST dump, the two discarded
method calls differ in exactly one field:

```
h.give()   #8221 kind=32 tk=22     <- tyVariant
h.me()     #8225 kind=32 tk=6      <- tyClass
```

A method returning an ATTRIBUTE (`return self.q`) types its result as
**`tyVariant` (22)**, not `tyClass` -- an attribute read on a NilPy object comes
back through the variant carrier -- so the object reference is leaked INSIDE a
variant and `PXXObjRelease` is the wrong verb for it. objtrace still shows the
retain (`R rc 1 -> 2`), so the +1 is real and owned; only the container differs.

**The next step is a `tyVariant` arm, and it needs its own ownership question
answered first, exactly as this one did.** `PXXVarClear` (`SXR_VAR`) is the
verb, and `variants.pas:162` says every overwritten Variant slot already goes
through it -- so spilling into a hidden `tyVariant` local may be sufficient on
its own, the way the `tyAnsiString` arm is, with the overwrite in a loop doing
the freeing. **Do not assume that.** Settle with objtrace whether a store into a
variant temp RETAINS: if it does, spill+overwrite is balanced and leaks nothing,
and if it does not, it is a move and the same borrowed/owned gate applies again.
Variants are pervasive in pylib, so the blast radius here is larger than the
class arm's -- gate on the same `UnitIsPyModule` provenance.

## THE INSTRUMENT NOTE THAT EXPLAINS THE TWO RETRACTED DEFECTS

`/home/neo/frank-user` is shared by more than one session and has ONE
`compiler/pascal26`. On 2026-09-15 the binary on disk was `295f6c473475dea8`
with a stamp claiming it, and `make compiler/pascal26` recomputed -- `converged
after 1 round(s)`, the real rebuild verb, not the stamp path -- and landed on
`d5a02f0bd32c` instead. Every probe run through the first binary is about a
compiler nobody can identify. Both retracted defects above came from that
window, and lekkerzeilen-c8 independently withdrew a whole family of
percent-format findings (a dropped list element, two SIGSEGVs, a TypeError) that
stopped reproducing the moment they re-ran against a known sha.

**Print `sha256sum compiler/pascal26` beside every number, and check the `make`
verb -- `converged` means a rebuild happened, `verified` means nothing was
built.** A foreign binary does not error. It answers.

## NOT A LEKKERZEILEN FIX, AND THAT WAS CHECKED RATHER THAN ASSUMED

Every discarded call on a hot path in the demo returns None, a bool, or an
existing attribute: `self.rig.update(dt)` (no return), `self.traffic.update(...)`
(no return), `self.boat.step(...)` (returns an existing object),
`self.rig_data()` (existing), `sail.raise_lower(dt)` (bool). Rank this on the
language, not on that demo.

(c8 withdrew a 137-site census of this that resolved "does this callee return a
value" BY METHOD NAME across the package, so one `update` returning something
marked every `update` in every class. The five above were checked individually.)
