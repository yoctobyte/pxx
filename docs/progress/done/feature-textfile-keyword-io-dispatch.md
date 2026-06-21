# Default `Text` file surface and file-handle IO dispatch

- **Type:** feature
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Relation:** Track A/B boundary follow-up for
  `lib-text-file-io-assign-rewrite`; needed by `examples/adventure`.

## Problem

The RTL can now provide a PAL-backed `Text` record and library procedures, but
FPC-style source expects the text-file surface to be available without an
explicit `uses textfile`, and `ReadLn`/`WriteLn` are lexer keywords. Calls like
these are either unresolved (`Assign`) or intercepted by the compiler before
ordinary procedure resolution:

```pascal
WriteLn(f, 'room=' + Player.RoomId);
ReadLn(f, line);
```

Today `examples/adventure` still stops at `Assign` being undefined. Once the
surface is visible, the builtin console lowering will also need to recognize a
file-handle first argument instead of treating all arguments as console values.

## Scope

- Expose the default Pascal text-file surface via a small, table-driven
  implicit RTL import, not by moving `textfile` into `compiler/builtin`.
  References to standard text-file names such as `Text`, `TextFile`, `Assign`,
  `AssignFile`, `Reset`, `Rewrite`, `Append`, `Close`, `CloseFile`, `Eof`, and
  `IOResult` should make the compiler load `lib/rtl/textfile.pas` as if it were
  an implicit unit.
- Keep `textfile` as a normal RTL unit backed by PAL. Do not make host file I/O
  part of the frozen builtin payload; bare/embedded targets must remain able to
  stub or omit the platform backend cleanly.
- Ensure `Text`, `Assign`/`AssignFile`, `Reset`, `Rewrite`, `Append`, `Close`/
  `CloseFile`, `Eof`, and `IOResult` resolve for FPC-style demo code.
- Detect `ReadLn`/`WriteLn`/`Write` with first argument of type `Text`.
- Lower those forms to the RTL text-file routines, or relax keyword interception
  enough that overload resolution can bind them normally.
- Preserve existing console `ReadLn`/`WriteLn` behavior and `WriteLn(StdErr, …)`.

## Acceptance

- A program using `var f: Text; Assign(f, path); Rewrite(f); WriteLn(f, 'x');
  Close(f); Reset(f); ReadLn(f, s);` without a special local wrapper round-trips
  through the PAL-backed RTL.
- Existing console read/write tests continue to pass.
- `examples/adventure` gets past the current file-IO keyword forms.

## Log

- 2026-06-20 - Opened while adding `lib/rtl/textfile.pas`. The Track B RTL
  primitives exist with explicit `TextReadLn`/`TextWriteLn`; this ticket covers
  the remaining default-surface and compiler-dispatch work needed for FPC-style
  syntax.
- 2026-06-21 - Direction clarified: keep implementation in `lib/rtl/textfile.pas`
  and add a compiler-owned implicit-RTL import table for the classic text-file
  surface. Avoid moving textfile into `compiler/builtin`; only keyword dispatch
  and default-name visibility belong in the compiler.
- 2026-06-21 - DONE (Track A). Implemented per the clarified direction;
  `lib/rtl/textfile.pas` unchanged (still PAL-backed, never frozen into builtin).
  Compiler side:
  - Implicit import: the `ParseProgram` token pre-scan sets `needsTextfile` when
    a `Text`/`TextFile` token appears in TYPE position (preceded by `:`, so
    `obj.Text` field access and `Text: AnsiString` field decls do NOT trigger —
    the latter matters because the compiler's own `TStrEntry.Text` field would
    otherwise pull textfile into the self-host). When set, `ParseUsesUnit
    ('textfile')` runs up front alongside the builtin/heap units, BEFORE
    declaration parsing — so `var f: Text` resolves and a proc-local Text gets
    normal managed-field (`Name: AnsiString`) zero-init. (An earlier attempt that
    loaded textfile mid-parse from `ParseTypeKind` corrupted the enclosing proc's
    codegen state and skipped that zero-init → segfault; the up-front load is the
    fix.) `needsTextfile` also forces `needsBuiltin` (numeric file writes format
    via StrInt/StrFloat). ESP (xtensa/riscv32) excluded.
  - Keyword dispatch: `TextIOFileSym` detects a BARE Text handle as the first
    Write/WriteLn/Read/ReadLn argument (next token `,`/`)` — `WriteLn(f.Name)`
    stays a console write). `write[ln](f, ...)` lowers to a sequence of
    `TextWrite` calls with the final value via `TextWriteLn` (single trailing
    newline); strings pass through, integers/floats go via StrInt/StrFloat.
    `read[ln](f, ...)` lowers to `TextReadLn` per destination. Console
    Write/WriteLn/`WriteLn(StdErr,…)` paths are untouched when no Text record is
    in scope (`IsRecordType('text') = REC_NONE`), so self-host is byte-identical.
  - Acceptance met: `var f: Text; Assign/Rewrite/WriteLn(f,…)/Close/Reset/
    ReadLn(f,s)` round-trips through PAL (regression `test/test_textfile.pas`,
    built `-Fulib/rtl/platform/posix`); console read/write tests stay green.
    `make test` green; self-host + threadsafe fixedpoint byte-identical.
  - Note: `examples/adventure` advances past all the file-IO keyword forms and
    `for sp in Player.Spells`; it now stops in the posix PAL backend at an
    `SYS_openat` arch-define resolution (a Track B platform-axis gap, separate
    from this ticket).
