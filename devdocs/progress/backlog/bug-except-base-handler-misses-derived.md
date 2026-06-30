# `except on E: BaseClass` does not catch a derived exception

- **Type:** bug (exception machinery — correctness) — Track A
- **Status:** backlog
- **Severity:** high — breaks the standard `on E: Exception do` catch-all; any
  code that raises a subclass of `Exception` and catches it with a base handler
  escapes as an unhandled exception (process aborts).
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

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
