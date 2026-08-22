---
track: A
prio: 35
type: feature
blocked-by: []
summary: "Slice 2 of bug-a-an-out-parameter-of-a-managed-type-is-not-cleared, which cleared out AnsiString / dynarray / interface by synthesising an empty-value ASSIGNMENT at the body head. Variant and managed records have no empty-value literal to assign — `v := Unassigned` renders as None rather than FPC's empty, and a record has no empty literal at all — so these two need the finalize-through-pointer primitive that trick was written to avoid."
---

# Finalize an `out` Variant and an `out` managed record

- **Type:** feature (completes a partial fix) — Track A
- **Status:** backlog
- **Opened:** 2026-08-22

## What already works, and why these two do not

[[bug-a-an-out-parameter-of-a-managed-type-is-not-cleared]] made `out` finalize
its parameter on entry the cheap way: a managed ASSIGNMENT already releases the
old value, and an assignment through a by-ref param already writes the caller's
variable, so `s := ''` / `d := nil` / `f := nil` at the head of the body IS the
finalize, with no new emitter and nothing per backend.

That works only for kinds with an empty-value literal. The remaining two:

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `out v: Variant` (caller had `'vv'`) | `[]` | `[vv]` |
| `out r: TRecM` (record with an AnsiString field, caller had `'q'`) | `[]` | `[q]` |

- **Variant**: `v := Unassigned` compiles but renders as `None`, not the empty
  FPC prints — so assigning it trades one divergence for another.
  `PXXVarClear(v: Pointer)` already exists in `builtinheap` and is the right
  primitive; it is simply not reachable from Pascal source
  (see [[bug-b-vartostr-is-missing-from-variants]] for the sibling export gap).
- **Managed record**: no empty literal exists. Needs a genuine finalize —
  release each managed field, then zero — through the caller's pointer.
  `RecordNeedsZeroInit` / `RecordHasManagedFields` already name the field set,
  and `IR_DEFAULT_MEM` already zeroes a record region at an address; what is
  missing is the release pass in front of it.

## Worth doing as one primitive, not two arms

Both want the same thing — *finalize the managed thing at this ADDRESS* — which
is also what an `out` param of a future managed kind will want, and close to
what scope-exit cleanup does for locals by frame offset. A single
address-taking finalize op would also give
`Initialize`/`Finalize` on a bare dynarray or Variant, which `ir.inc:7526`
currently refuses outright with "not implemented yet; assign nil instead, or
wrap it in a record (feature-a-finalize-for-bare-dynarray-and-variant)". Check
whether that ticket and this one are the same work before starting either.

## Side question this turned up

An empty Variant printing `None` is a NilPy spelling reaching Pascal output;
FPC prints the empty string. Worth its own look — it is not specific to `out`.

## Gate

Track A's, plus the two rows above matching fpc 3.2.2 added to
`test/test_out_parameter_of_a_managed_type_is_cleared.pas`, and its ARC round
trip extended to a Variant and a managed record (a second owner of the record's
string field must survive the clear).
