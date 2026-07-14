---
summary: "Record-cast lvalue/rvalue field access ignores field offset — tqwordrec(q).high reads and writes offset 0"
type: bug
prio: 55
---

# Record-cast field access resolves every field at offset 0 (SILENT wrong values)

- **Type:** bug (Track P — Pascal frontend / shared parser lowering)
- **Status:** working
- **Opened:** 2026-07-14
- **Found by:** Track B FPC-conformance burn-down (tint642.pp), filed per
  "T/B owns the finding, the owning lane owns the bug".

Casting a scalar variable to a record type and accessing a field —
`trec(q).field` — compiles, but **every field resolves at offset 0**, both as
rvalue and as lvalue. No diagnostic; classic silent-wrong-value shape (compare
the [[project_forward_pointer_field_offset_zero_landmine]] b338 family: same
symptom, different resolution path).

## Repro (minimal, no suite needed)

```pascal
type
  tqwordrec = packed record
    low: cardinal;
    high: cardinal;
  end;
var q: qword;
begin
  tqwordrec(q).high := $12345678;
  tqwordrec(q).low := $9ABCDEF0;
  writeln(tqwordrec(q).high);   { FPC: 305419896 ($12345678) }
  writeln(tqwordrec(q).low);    { FPC: 2596069104 ($9ABCDEF0) }
  writeln(q);                   { FPC: 1311768467463790320 }
end.
```

pxx (v8479f4af + this session): all three writelns print `2596069104` — the
`.high` store landed on the low dword and the `.high` load read it back.

## Impact

- `tint642.pp` (FPC testsuite, qword arithmetic torture): its `assignqword` /
  `dumpqword` helpers are built on `tqwordrec(q).high/.low`; every downstream
  "failure" it reports is this one bug. Skip-list entry updated to point here.
- `tint643.pp` uses the identical idiom.
- Any real-world code using the classic record-overlay cast (`TInt64Rec`,
  `TDoubleRec` style) gets silently wrong halves.

## Note for the fix

`tqwordrec(q).high := x` on a VARIABLE is a Delphi/FPC value-typecast lvalue:
address of `q` reinterpreted as the record, so the field address must be
`@q + field offset`. Sweep sibling dispatch branches: rvalue read, lvalue
store, `@trec(q).field`, nested `trec(q).field.sub`, and the cast-of-cast
form — per [[feedback_sweep_sibling_dispatch_branches]].
