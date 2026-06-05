# Operator-result into an inferred `var` drops record fields

**Found:** 2026-06-05, while drafting the dialect showcase in `docs/dialect.md`.
**Status:** discovered (folder = status).

## Symptom

Assigning the result of an overloaded operator straight into an auto-typed
inline variable miscompiles for multi-field records — only the first field
survives.

## Minimal repro

```pascal
type
  TVec = record X, Y: Integer; end;

operator + (a, b: TVec): TVec;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;

var a: TVec; var b: TVec;
a.X := 1; a.Y := 2;
b.X := 3; b.Y := 4;
var c := a + b;          { inferred type }
writeln(c.X, ',', c.Y);  { prints 4,0 — expected 4,6 }
```

## Workaround

Type the target explicitly (`var c: TVec := a + b;`, or a normal `var` block),
which round-trips both fields.

## Suspected cause (unverified, not investigated)

The inferred temp for the operator return appears to use a word-sized slot/copy
instead of the full record size, so fields past the first qword are lost. Likely
the auto-typed-var inference path rather than operator dispatch itself, since an
explicitly typed target works.

## Notes

- No regression test yet. Compiler not modified.
- Documented as a known gap in
  [`docs/dialect.md`](../../dialect.md) ("Where we're headed").
