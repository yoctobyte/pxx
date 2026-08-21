---
track: U
prio: 60
type: decide
blocked-by: []
summary: "SIX open Track A tickets (two of them use-after-frees) are all the same missing capability: a COM interface held inside an aggregate is invisible to every container-level retain/release walk. The one fix is blocked on a heap-lock question that was attempted once and reverted. Which strategy — reentrant lock, unlocked interface pass, or a copy-site-only stopgap — and who validates it against the threading stress tests?"
status: decided
owner: user
---

# Interface members in aggregates: which lock strategy?

- **Track U** — a decision, not work. Blocks six Track A tickets.
- Raised 2026-08-20 after a differential sweep of interfaces-in-containers turned
  up six defects that are all one missing capability.

## What is blocked

| ticket | severity |
| --- | --- |
| `bug-a-a-record-copy-does-not-retain-an-interface-field` | **use-after-free** |
| `bug-a-two-function-result-interfaces-into-a-local-dyn-array-segfault` | **crash** |
| `bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit` | leak |
| `bug-a-a-local-dynamic-array-of-interfaces-is-not-released-at-scope-exit` | leak |
| `bug-a-setlength-shrink-does-not-release-dropped-interface-elements` | leak |
| `bug-a-class-managed-fields-not-finalized-on-destroy` | leak (holds the blocker) |

Three more in the same family were fixable WITHOUT touching the lock and are
already fixed and gated today — the zero-init trio plus the dyn-array-assign
crash. What remains is exactly the part that needs a release to run somewhere
safe.

## The state of the machinery

- The record descriptor's runtime walk (`PXXRecordRetain` / `PXXRecordRelease`)
  knows member kinds **1 = String, 2 = DynArray, 3 = Record**. There is **no
  interface kind**. (An earlier ticket describes the kinds as including
  Interface; the runtime `case` does not have it. Worth correcting there.)
- `EmitManagedRecordRetain` / `EmitManagedRecordReleaseLocked` both early-exit on
  `RecordHasManagedFields`, which deliberately excludes interface fields — so for
  a record whose only refcounted member is an interface, the ARC copy is not even
  selected; it takes the raw `IR_COPY_REC`.
- The blocker: record-field finalization runs under the **non-reentrant heap
  spinlock**, and `PXXIntfRelease -> _Release -> Free -> FreeMem` re-acquires it
  and spins forever. Confirmed under `{$threadsafe on}`. A previous attempt at
  the COM record-field case (`cb2ed843`) hit exactly this and was reverted
  (`87108477`) back to a benign leak.
- Scope-exit interface LOCALS and by-value param temps are already correct and
  threadsafe, because `EmitManagedLocalCleanup` does NOT wrap them in the lock.

## The fork

**(a) Reentrant heap lock** — owner + depth, needs a per-thread identity / TLS.
Fixes every site at once and makes the whole family fall out. Highest blast
radius: it changes the allocator's core locking for all code, not just ARC.

**(b) Unlocked interface pass at every finalize/copy site** — emit the interface
retain/release BEFORE acquiring the lock, leaving the string/dynarray pass
locked as today. This is the option the existing ticket already names. Needs
descriptor member kind 4 (plus the iface id) and matching runtime support, and
must be repeated at every site across six backends.

**(c) Copy-site-only stopgap (new; my recommendation to consider first)** — fix
only the *use-after-free* half now, and leave finalization leaking exactly as it
already does by design. At the record-copy site the field offsets and iface ids
are known at COMPILE time, so the compiler can emit a short inline sequence —
`PXXIntfAddRef(src+off, id)` per interface field, then `PXXIntfRelease(dest+off,
id)` — **before** `EmitAcquireHeapLock`, with no descriptor or runtime change at
all. Needs a new predicate (`RecordHasManagedFields` OR has an interface field)
to select the ARC copy in the first place.
Trade: a record copy then RETAINS but never releases, so each copy leaks one
reference instead of dangling one. That is strictly better than a UAF and is the
same benign-leak-over-correctness trade this area already made deliberately.
Cost: it is a fourth partial in an area that already has three, so it is only
worth doing if (a)/(b) are genuinely far off.

## What I could not do, and why I am asking rather than guessing

The existing ticket states both real options are "heap-critical and must be
validated by the threading stress tests, not just the single-threaded native
tier." A development track gates on `gate.sh quick`, which does not run those.
So this needs either a decision to route it through Track T's heavier tiers, or
an explicit owner who will validate it.

Guessing here means re-running `cb2ed843`'s revert.

## Recommendation

**(a) if the allocator work is acceptable — it deletes the whole family and every
future instance of it.** The recurring shape all day was "one predicate answering
two questions"; a reentrant lock removes the reason the questions were ever
split. If (a) is off the table for now, take (c) to kill the two crashes, and
leave the leaks filed against (b)/(a).

Either way the two **use-after-frees** should not sit in the backlog at leak
priority — they are silent wrong-memory bugs, and one of them
(`b := a` on a record with an interface field) is ordinary-looking Pascal.

## 2026-08-21 — this is now the LAST blocker in its family (Track A)

The COM-interface-in-a-container family landed today without waiting on this
decision, because the array cases had an escape route this one does not:

- **static arrays** release outside any lock, so kind 4 is simply on;
- **dynamic arrays** release under the lock, so `ManagedElemKindLocked`
  (`compiler/symtab.inc`) refuses kind 4 when `ThreadSafeMode` is set — the
  pre-existing leak instead of a deadlock, asserted in the Makefile including
  that `--threadsafe` terminates.

So the residual is now precise and small: **under `--threadsafe` on x86-64, a
DYNAMIC array of interfaces leaks its elements, and a record's interface field
is neither copied with a retain nor finalized.** Everything else in the family
is correct and FPC-matched.

That makes this decision worth more than it was: resolving it closes
[[bug-a-a-record-copy-does-not-retain-an-interface-field]] (the only family
member still open), removes the `ThreadSafeMode` gate in `ManagedElemKindLocked`,
and retires the residual `bug-a-class-managed-fields-not-finalized-on-destroy`
recorded for record fields — three things, one answer.

The two options are unchanged and both are now implemented ONCE somewhere in
the tree, which should make the choice cheaper than when this was filed:

- **(a) reentrant heap lock** (owner + depth). The blocker used to be "needs a
  per-thread identity / TLS, which this runtime does not have". **It has TLS
  now** — `feature-a-thread-local-storage-via-clone-settls` and
  `feature-a-tls-block-for-the-main-thread` landed 2026-08-20, `gs`-based, with
  a slot convention and free slots reserved. That removes the stated obstacle;
  what remains is whether an owner/depth check on the hot allocator path is
  acceptable, which is a measurement, not a judgement.
- **(b) a separate unlocked interface pass before the locked one** — already
  shipped for CLASS fields (`PXXClassFinalize` runs its kind-4 pass first and
  unlocked) and known to work.

Recommendation: **(b) for the containers** (it is the proven shape and needs no
allocator change), and evaluate (a) separately as an allocator question now that
TLS exists, rather than as a prerequisite for this family.

## ANSWER (user, 2026-08-21)

**(b) — a separate unlocked interface pass, for the containers AND the record
case. (a) is split out as its own allocator ticket, aimed at what it is actually
for.**

Implementation: [[bug-a-a-record-copy-does-not-retain-an-interface-field]]
(unblocked by this answer; it is the only family member still open).
The allocator question: [[feature-a-reentrant-heap-lock-and-per-thread-arenas]].

### Why (b) closes the record case, which had "no escape route"

The record ticket's 2026-08-21 note says it cannot use the dyn-array gate
because *"the record descriptor's managed-field predicate is shared with
FINALIZATION — so widening it turns on both halves at once, and the
finalization half is what deadlocks."*

Under (b) that reasoning stops applying: the interface retain **and** release
both move ahead of `EmitAcquireHeapLock`, so widening the predicate no longer
enables a *locked* release. The deadlock is removed rather than gated around,
which means the record case needs no `ThreadSafeMode` refusal of its own and
the use-after-free is fixed in every build — not traded for a leak the way
option (c) proposed.

### Why (a) is not the prerequisite, measured

Two facts checked on 2026-08-21 (static reading, not a build):

- **(a)'s stated blast radius was overstated.** `EmitAcquireHeapLock` opens with
  `if ThreadSafeMode then` — a default build emits **no heap lock at all**. So a
  reentrant lock does not "change the allocator's core locking for all code"; it
  changes it for `--threadsafe` builds, which already pay for the lock. The
  uncontended cost of an owner+depth check is a few instructions against one
  `lock xchg`.
- **But (a) must be built twice.** x86-64 uses a hand-emitted TTAS+PAUSE blob in
  `ir_codegen.inc`; i386 uses an entirely separate Pascal spinlock
  (`PXXHeapSpin`, under `PXX_TS_SOFTLOCK`) because it has no lock blobs. One
  concept, two implementations, which would have to stay in step.

The decisive point is that **(a)'s real payoff was never this bug family**.
`EmitAcquireHeapLock`'s own comment names the actual prize: *"it does NOT make
the allocator scale — that needs per-thread arenas, which needs real TLS, which
this runtime does not have yet."* That comment is **stale** — TLS landed
2026-08-20 — and per-thread arenas are a far larger win than closing one leak.
Gating a memory-safety fix on an allocator redesign gets neither; doing (b) now
frees (a) to be judged on what it is for.

### Correction to this ticket's own framing

The 2026-08-21 update above describes the residual as *"a record's interface
field is neither copied with a retain nor finalized"*, which reads as a benign
leak. It is not: the missing **retain on copy** is a real use-after-free, it is
**not** confined to `--threadsafe`, and the frontmatter summary calling it that
is correct. Only the dyn-array element leak is threadsafe-only. Do not let the
"everything else landed" framing downgrade the one that is left.
