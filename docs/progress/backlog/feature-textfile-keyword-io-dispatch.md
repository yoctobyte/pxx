# File-handle `ReadLn`/`WriteLn` dispatch for `Text`

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** Track A follow-up for `lib-text-file-io-assign-rewrite`; needed
  by `examples/adventure`.

## Problem

The RTL can now provide a PAL-backed `Text` record and library procedures, but
`ReadLn` and `WriteLn` are lexer keywords. Calls like these are intercepted by
the compiler before ordinary procedure resolution:

```pascal
WriteLn(f, 'room=' + Player.RoomId);
ReadLn(f, line);
```

Today the builtin console lowering treats all arguments as console values, so a
file-handle first argument cannot dispatch to the text-file RTL.

## Scope

- Detect `ReadLn`/`WriteLn`/`Write` with first argument of type `Text`.
- Lower those forms to the RTL text-file routines, or relax keyword interception
  enough that overload resolution can bind them normally.
- Preserve existing console `ReadLn`/`WriteLn` behavior and `WriteLn(StdErr, …)`.

## Acceptance

- A program using `var f: Text; Assign(f, path); Rewrite(f); WriteLn(f, 'x');
  Close(f); Reset(f); ReadLn(f, s);` round-trips through the PAL-backed RTL.
- Existing console read/write tests continue to pass.
- `examples/adventure` gets past the current file-IO keyword forms.

## Log

- 2026-06-20 - Opened while adding `lib/rtl/textfile.pas`. The Track B RTL
  primitives exist with explicit `TextReadLn`/`TextWriteLn`; this ticket covers
  the remaining compiler dispatch needed for FPC-style syntax.
