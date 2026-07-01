# `except on E: BaseClass` does not catch a derived exception

- **Type:** bug (exception machinery — correctness) — Track A
- **Status:** done — fixed 2026-07-01, pin v128
- **Severity:** high — breaks the standard `on E: Exception do` catch-all; any
  code that raises a subclass of `Exception` and catches it with a base handler
  escapes as an unhandled exception (process aborts).
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Resolution

Confirmed the predicted cause exactly: `IR_EXC_MATCH`'s codegen compared the
raised class id for identity only. Fix reuses the existing `is`/`as` ancestry
walk (`IsClassDescOrSelf`, already used by `IRLowerClassMatch`) at IR-lowering
time (`ir.inc`'s `AN_TRY_EXCEPT` case): for each `on E: T` handler, enumerate
every class descending from `T` (closed-world, compile-time) and emit one new
`IR_EXC_MATCH_HIT` node per descendant — a positive-polarity sibling of
`IR_EXC_MATCH` (jumps *into* the handler body on a match, instead of jumping
*away* on a mismatch) — followed by the original exact-match `IR_EXC_MATCH`
for `T` itself, whose existing fall-through lands on the same body label.

New IR opcode `IR_EXC_MATCH_HIT` (`defs.inc`), implemented in all 4 backends
that support exceptions (x64, i386, arm32, aarch64 — mirrors each target's
existing `IR_EXC_MATCH` codegen with the branch condition flipped: `je`/`jz`/
`beq`/`b.eq` instead of `jne`/`jnz`/`bne`/`b.ne`). riscv32/xtensa don't
implement exceptions at all (pre-existing, unaffected).

Verified: the `poly` example from this ticket, plus a fuller regression
(`test/test_except_derived_caught_by_base.pas`) covering direct-derived,
two-level-derived (grandchild), exact-match-still-works, most-specific-first
ordering across multiple `on` clauses, and a negative case (unrelated sibling
class not caught by an unrelated handler, falls through to the real
catch-all) — all pass on x86-64 natively and the class-*matching* logic was
independently confirmed correct on i386/arm32/aarch64 via cross-compile +
QEMU.

**Two separate, pre-existing bugs found (not fixed) while cross-verifying,
filed separately:** [[bug-i386-try-except-segfault]] — i386 SIGSEGVs on a
basic `try...except` block in some code shapes (confirmed on the pre-fix
baseline, unrelated to this fix); and `E.Message` returns empty on all 3
cross targets even without a crash (x86-64 native is correct) — noted in the
same ticket since found together, may need splitting out.

Full `make test` green (x86-64), self-host byte-identical (gen1==gen2, no
lag), `make stabilize` green.

## Symptom

An `except on E: T do` handler only fires when the raised object's class is
*exactly* `T`. A handler for a **base** class does not catch instances of a
**derived** class — the opposite of Delphi/FPC semantics (a handler catches the
named class and everything derived from it).

```pascal
program poly;
uses sysutils;
type EMy = class(Exception) end;
begin
  try raise EMy.Create('derived');
  except on E: Exception do writeln('caught:', E.Message); end;   { never prints }
  writeln('done');                                                { never reached }
end.
```

```
Unhandled exception
```

Expected: prints `caught:derived` then `done`.

## Isolation (all against stable v97)

| Raised class | Handler | Result |
| --- | --- | --- |
| `Exception` | `on E: Exception` | **OK** (caught) |
| `EMy(Exception)` | `on E: EMy` (exact) | **OK** (caught) |
| `EMy(Exception)` | `on E: Exception` (base) | FAIL — unhandled, process aborts |

So raise/except itself works; the defect is purely the **class match** test in
the `on` clause: it compares the raised class for identity instead of walking the
ancestry (is-a). A bare `except ... end` (no `on`) still catches everything.

## Likely cause

The `on E: T` dispatch compares the exception object's class pointer/VMT to `T`'s
for equality, rather than testing `RaisedClass.InheritsFrom(T)` (walk the parent
chain, the same predicate the `is` operator uses — and `is` works, see p3 in the
sweep). Reuse the `is`/`InheritsFrom` ancestry walk for `on`-clause matching.

## Track B impact

This blocks idiomatic library error handling. A library function that raises a
subclass of `Exception` (the FPC-correct `EConvertError`, `EDivByZero`, …) cannot
be caught by the conventional `try ... except on E: Exception do` catch-all —
only an exact `on E: <ExactClass> do` works. This is almost certainly *why* the
RTL conversion helpers (`StrToInt`, `StrToFloat`) were deliberately written to
return a silent `0` on malformed input (see their interface comments) instead of
raising: a raised subclass would escape any catch-all and abort the process.
Until this lands, those helpers cannot be made FPC-idiomatic (raise on bad
input). Filed as a Track A blocker for that library work.

## Acceptance

- `poly` above prints `caught:derived` then `done`.
- `on E: Exception do` catches any subclass; exact-type handlers still work;
  most-specific-first ordering across multiple `on` clauses is honoured.
- Add a regression test (`test/test_except_derived_caught_by_base.pas`) wired into
  `make test`; self-host stays byte-identical.
