# Default `Text` file surface and file-handle IO dispatch

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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

- Decide how the default Pascal text-file surface is exposed:
  compiler prelude/system import, `sysutils`, or another explicit compatibility
  mechanism.
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
