---
track: A
prio: 35
type: bug
blocked-by: []
summary: "MEASURED 2026-09-07. A record holding an ARC field (AnsiString, dynamic array, COM interface) ALONGSIDE a field whose type declares `class operator Copy` does not run that operator on assignment -- it takes the fused IR_COPY_REC_MANAGED byte copy instead. `TMixed = record s: AnsiString; a: TA; k: Integer` with TA declaring Copy: fpc 3.2.2 prints `A.Copy src=42 dst-on-entry=99` and leaves `m2.a.id=99`; pxx prints nothing and leaves `m2.a.id=42`. THIS IS A DELIBERATE REFUSAL, NOT AN OVERSIGHT: IRRecCopyWithHoles and IRArrayElemCopyOps both exit on RecordHasManagedFields, because the hole-punching they do needs the copy expressed as BYTE RANGES and IR_COPY_REC_MANAGED is a single fused retain-release-copy op implemented on six backends that takes a RECORD ID and walks that record's layout descriptor. It cannot be handed a range. THE REFUSAL IS THE OUTER RECORD'S ANSWER and RecordHasManagedFields recurses, so a record whose only managed member sits INSIDE the operator field is refused too -- conservative in the direction that preserves today's behaviour. TWO ROUTES OUT, neither costed: a second descriptor kind describing a SUBRANGE of a record, or an unrolled per-field ARC sequence at the IR level for the mixed case only. The non-ARC halves are fixed and pinned (test_mgmt_operators_copy_contained, test_mgmt_operators_copy_array); this is what is left of bug-a-a-whole-record-assignment-does-not-run-a-contained-fields-copy-operator."
status: open
---

# A record mixing an ARC field with a `Copy`-operator field skips the operator

## Repro

```pascal
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TA = record
    id: Integer;
    class operator Copy(constref src: TA; var dst: TA);
  end;
  TMixed = record
    s: AnsiString;      { <-- the ARC field is what causes the refusal }
    a: TA;
    k: Integer;
  end;
```

```
fpc 3.2.2:   A.Copy src=42 dst-on-entry=99
             m2.s=from-one m2.a.id=99 m2.k=7
pxx:         m2.s=from-one m2.a.id=42 m2.k=7
```

`m2.a.id` is the discriminating column: 99 means the operator ran and delegated
the field (it assigns nothing in the probe), 42 means the bytes arrived.

## Why it is refused rather than broken

The two non-ARC halves landed 2026-09-07 by punching the copy: the byte ranges
BETWEEN the operator fields as `IR_COPY_REC`, plus one operator call per field.
That works because `IR_COPY_REC` takes an address and a length.

`IR_COPY_REC_MANAGED` does not. It takes `(dstAddr, srcAddr, recId, size)` and
the backends walk `recId`'s layout descriptor to retain the source's handles and
release the destination's. There is no way to say "do that for bytes 0..7 and
16..24 but not 8..16", so the mixed record keeps the fused op and the operator
never fires.

**The refusal is deliberately the OUTER record's answer** — `RecordHasManagedFields`
recurses, so a record whose only `AnsiString` sits inside the `Copy` field is
refused as well. That is more conservative than it needs to be and it preserves
today's behaviour rather than inventing a new one.

## Two routes, neither costed

1. **A descriptor kind for a SUBRANGE** — let `IR_COPY_REC_MANAGED` carry a
   byte window, so the punch works for it too. One new member kind, six backends
   to teach, and the descriptor is a bootstrap interface (see
   `compiler/defs.inc`'s record-descriptor block: extend inert, never grow the
   header).
2. **Unroll the ARC walk at the IR level** for the mixed case only — emit the
   per-field retain/release inline instead of calling the fused op, so the
   operator fields can be skipped. No descriptor change, more IR per site, and
   it duplicates a walk that already exists in the runtime.

## What is already pinned, so a fix here has controls

`test/test_mgmt_operators_copy_contained.pas` and
`test/test_mgmt_operators_copy_array.pas` (both in `test-core`, both with fpc
3.2.2's output as `.expected`) cover the non-ARC record and array shapes. A fix
for this ticket must leave both byte-identical and add the mixed rows to one of
them. **The operator must PRINT** — a value check cannot see this defect, since
an operator that dutifully copies its fields is indistinguishable from the byte
copy that would have moved the same bytes.
