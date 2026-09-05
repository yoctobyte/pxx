---
track: A
prio: 35
type: feature
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-05
found-by: frank-optimize, landing the record half of feature-opt-inline-float-and-record-returning-leaves
summary: "Record-returning leaves inline at -O3 (78fc2dab3) and deliver 1.54x on the dd kernels against a 3.0-3.3x hand-inlined bound -- so 40-50% of the available win is still on the table, and it is ONE mechanism: the splice allocates a Result temp with the callee's layout and copies out of it, where hand-inlining writes the caller's destination directly. Measured, not inferred: same arithmetic, bit-identical output, only the temp differs."
---

# Splice a record Result into the caller's destination, not a temp

- **Type:** feature (optimizer — **Track O**, file-owned by **Track A**).
- Found 2026-09-05 while landing the record half of
  [[feature-opt-inline-float-and-record-returning-leaves]].

## The gap is measured, and it is one mechanism

The dd kernels, same arithmetic three ways, control and change built from the
same base (`converged after 1 round(s)` each), output bit-identical in all three:

| | unloaded, min-of-7 | user CPU, min-of-9 |
| --- | --- | --- |
| out-of-line calls (control) | 0.3264s | 0.30s |
| **inlined by the compiler today** | **0.2114s** | **0.18s** |
| the same arithmetic hand-inlined | 0.0994s | 0.10s |

**1.54x delivered against a 3.0-3.3x bound: 50-60% captured.** The remainder is
not spread across the pass; it is the Result temp. `IRInlineExpand` allocates a
scratch record carrying `ProcRetRecId`, the spliced body writes its fields, and
the caller then copies out of it. Hand-inlining has no temp because the fields
are written where they are wanted.

## Why it is filed rather than done

It is a different change from admission. Admission decides WHETHER a body may be
retained; this decides WHERE its Result lands, which means teaching the splice
about the caller's destination — an assignment target, a field of another
record, an argument slot, or nothing at all when the result is discarded. Each
is a distinct case and at least one (discarded result) can skip the store
entirely.

**The hazard to design against first:** the per-field definite-assignment guard
in `TryRetainInlineRecBody` currently protects a temp nobody else can see. Write
into the caller's destination and a body that leaves a field unwritten no longer
produces stack garbage in a scratch — it produces a PARTIAL UPDATE of a live
variable, silently, with the other fields correct. `test_inline_record_result`'s
`HalfOnly` row is the positive control that exists for exactly this and must be
extended to assert the destination is untouched, not merely that the call did not
inline.

## Not a prerequisite

The 1.54x is banked and correct without this. This is the other half of the
prize, with a measured size rather than an inferred one.
