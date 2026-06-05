# Record-valued operator result is miscompiled (aggregate-return ABI)

- **Type:** bug (also in filename)
- **Status:** working (folder = status)
- **Owner:** Claude (Opus 4.8)
- **Found:** 2026-06-05, while drafting the dialect showcase in `docs/dialect.md`.

## Log

- 2026-06-05 — discovered and written up. Not started.
- 2026-06-06 — claimed. Root narrowed by a repro matrix: the bug is **not**
  inferred-var-specific. A record-valued `function` return works (global/local,
  8- and 12-byte); a record-valued **operator** return is miscompiled — into an
  inferred var it drops the 2nd field (`4,0`), into an explicit var (local or
  global) it **segfaults**. So the operator call path does not use the
  hidden-destination aggregate-return ABI that function calls use. The earlier
  "explicit typing is the workaround" note is WRONG (explicit segfaults). Next:
  find where function calls set up the aggregate hidden-dest and why operator
  lowering diverges. (reproB / whole-record array copy does NOT reproduce — see
  `bug-whole-record-copy-main-body-noop`; likely already fixed.)

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
