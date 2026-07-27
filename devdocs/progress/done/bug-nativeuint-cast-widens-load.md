---
summary: "core: NativeUInt/NativeInt(field) loads EIGHT bytes from a four-byte field"
type: bug
track: A
prio: 80
---

# `NativeUInt(rec.intField)` read the neighbouring field too

- **Type:** bug (IR, value typecast) — **Track A**
- **Found:** 2026-07-27, chasing a Counter segfault in NilPy; the bug is pure
  Pascal and target-independent.
- **Class:** silent memory corruption.

## Repro (no NilPy involved)

```pascal
type TR = class n: Integer; b: Boolean; end;
...
r.n := 16; r.b := True;
WriteLn(Int64(NativeUInt(r.n)));   { pxx: 4294967312 (0x1_00000010) — expected 16 }
```

`Int64(...)`, `QWord(...)` and `Cardinal(...)` were all correct; only the
pointer-sized names were wrong.

## Cause

ir.inc's `AN_PTR_CAST` widening branch tested `castTk = tyInt64 or tyUInt64`.
`tyNativeInt` / `tyNativeUInt` are distinct kinds, so they missed it and fell
through to the same-width branch, whose final action is an in-place RETAG of
the operand IR node (`IRTk[Result] := ASTTk[node]`). Retagging a memory LOAD
changes its width: the four-byte `movsxd` of the field became an eight-byte
`mov`, dragging in whichever field the record declares next. The float branch
right below documents exactly this hazard for float<->float casts; the ordinal
path needed the same care.

## Fix

Include the pointer-sized pair in the widening branch (guarded to when they
really are 64-bit, so a 32-bit target still uses the narrowing branch), and
treat a source already tagged NativeInt/NativeUInt as full-width.

## Impact

pylib's `TPyDict` hit it: `mask := NativeUInt(d.FHashCap) - 1` picked up the
adjacent `FCounterMode` byte, so every hash mask on a **Counter** carried bit
32 and the first `store` indexed the hash table off into unmapped memory. Any
record with an Integer field followed by another field could be affected.

## Gate

`test/test_nativeint_cast_field.pas` (in `make test`), self-host
byte-identical, `tools/gate.sh quick`.
