# Record-valued operator result is miscompiled (aggregate-return ABI)

- **Type:** bug (also in filename)
- **Status:** done (folder = status)
- **Owner:** Claude (Opus 4.8)
- **Found:** 2026-06-05, while drafting the dialect showcase in `docs/dialect.md`.

## Fix

Commit `2cf92fb`. Two distinct bugs, both fixed:

1. **Dispatch tag mismatch.** `ParseOperatorDef` registered every overload under
   `tyClass`, but `FindOpOverload` is queried with the operand's real kind
   (`tyRecord` for records). Record operators never matched → `a + b` lowered to
   a scalar qword/int binop (explicit → `copy_rec` read the int as an address →
   segfault; inferred → `4,0`). Now registers with the operand's actual kind.
2. **Untyped operator binop.** The parser never typed the operator binop as the
   operator's result type and `ResolveNodeRec` had no `AN_BINOP` case, so an
   inferred `var c := a + b` got `tyInteger`/`REC_NONE` → wrong size → garbage.
   `ParseSimpleExpr`/`ParseTerm` now type a record/class operator binop as
   `Procs[op].RetType`; `ResolveNodeRec` resolves it to the result record id.

Regression: `test/test_op_record_result.pas` (in `make test`). Full bootstrap
byte-identical fixedpoint + `make test` + `fpc-check` green.

**Out of scope (separate, pre-existing — filed as
`bug-record-byvalue-arg-truncation`):** by-value record params >8 bytes
truncate, `const` operator params segfault, and an operator result reused
directly as an operand is garbled. All are the orthogonal record-by-value
arg-passing path, not the result path fixed here.

## Log

- 2026-06-05 — discovered and written up. Not started.
- 2026-06-06 — claimed. Root narrowed by a repro matrix: the bug is **not**
  inferred-var-specific. A record-valued `function` return works (global/local,
  8- and 12-byte); a record-valued **operator** return is miscompiled — into an
  inferred var it drops the 2nd field (`4,0`), into an explicit var (local or
  global) it **segfaults**. So the operator call path does not use the
  hidden-destination aggregate-return ABI that function calls use. The earlier
  "explicit typing is the workaround" note is WRONG (explicit segfaults).
- 2026-06-06 — fixed (2cf92fb): operator dispatch tag + operator-binop typing /
  `ResolveNodeRec`. Verified, regression added, full gate green. Moved to done/.
  (reproB / whole-record array copy never reproduced — see
  `bug-whole-record-copy-main-body-noop`.)

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
