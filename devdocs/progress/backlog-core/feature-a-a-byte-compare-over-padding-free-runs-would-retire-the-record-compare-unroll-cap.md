---
track: A
prio: 30
type: feature
status: backlog
owner: ""
created: 2026-09-07
found-by: frankA
tags: [records, equality, codegen, code-size]
blocked-by: []
summary: "Record `=` is expanded field-wise and an array member is UNROLLED, one comparison per element, at ~55 bytes of emitted code per leaf (measured x86-64, default -O, flat from 100 to 1280 leaves -- linear, no knee). REC_CMP_UNROLL_MAX = 64 bounds that at ~3.5KB per comparison site, and above the cap the comparison falls back to the pre-2026-09-07 first-word compare and answers WRONG for records differing past the first word -- with a warning, so the cliff is visible, but still wrong. The fix is NOT a bigger cap. An array of a scalar has NO INTERIOR PADDING, which is exactly what makes a byte-wise compare unsafe for a whole record (padding is undefined, measured: field-equal records differ in 7 of 16 bytes) and SAFE over that run: a byte-compare over any contiguous padding-free run is O(1) code with no cap. It needs a PXXMemCmp, which does not exist -- compiler/builtin/builtinheap.pas declares PXXMemMove, PXXMemZero and PXXMemCopy only. Low prio because the population is empty today: the cap warning fires ZERO times across test-core."
---

# What has to be decided, not just written

`PXXMemCmp` itself is small. The judgement is **which runs are padding-free**,
and getting that wrong reintroduces the defect the whole family exists for.

A run is safe to byte-compare when every byte in it is part of a field's value.
That holds for an array of a scalar whose element size equals its storage size,
and it does NOT hold for:

- an array of RECORDS, unless the element record is itself gap-free
  (`sum of field spans = RecSize`, recursively) — an `array[0..99] of
  record b: Byte; y: Int64 end` has 7 undefined bytes per element
- an array of `AnsiString` or any managed type — a handle compare is identity,
  not content, which is the thing the field-wise walk fixed
- any run that crosses a field boundary where the compiler inserted alignment
  padding

So the deliverable is a predicate — "is this field, or this contiguous span of
fields, gap-free" — and it belongs beside `RecFieldCmpSpan` in `ir.inc`, which
already computes the spans the overlap test uses.

**A gap-free predicate is also worth more than this one caller.** The same
question decides whether a record can be hashed or serialised as bytes, and
`RecordHasManagedFields` is the existing shape to model it on.

## Acceptance

`record v: array[0..999] of Integer end`, differing at the LAST element,
expected FALSE on every target, and the emitted code must NOT grow with the
element count — measure it the way `REC_CMP_UNROLL_MAX`'s comment records
(executables, ~20 comparison sites per build to clear the page quantum;
`--emit-obj` objects report a constant 64 bytes and measure nothing).

The must-fail row is the padded one: `record v: array[0..999] of record
b: Byte; y: Int64 end end` with identical field values must still compare EQUAL.
If a byte-compare is taken over that run it answers FALSE, and that is the
defect this ticket must not reintroduce.
