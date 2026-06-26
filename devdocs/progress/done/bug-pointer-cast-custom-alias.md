# Pointer cast on custom Char pointer aliases fails to skip string length prefix

- **Type:** bug
- **Status:** DONE 2026-06-20
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** surfaced in gtk3widgets.pas when using typed pointer casts of custom aliases (like `PC = ^Char; PC(s)`) instead of literally `PChar(s)` or `PAnsiChar(s)`.

## Problem

When a custom alias to `^Char` is defined (e.g. `type PC = ^Char;`), casting an inline string (`tyString`) using this alias (e.g. `PC(someString)`) does not add the `+8` offset required to skip the 8-byte length prefix. As a result, the cast yields a pointer to the length prefix itself rather than to the NUL-terminated character data. This causes external C/GTK functions to receive control/length bytes instead of the actual string contents.

## Reproduction

```pascal
program repro;
type
  PC = ^Char;
var
  s: string;
  p1: PChar;
  p2: PC;
begin
  s := 'Hello';
  p1 := PChar(s); // correctly points to 'H' (adds +8 offset)
  p2 := PC(s);    // BUG: points to the 8-byte length prefix (first byte contains length 5)
end.
```

## Root cause

In `compiler/parser.inc` line 3256:
```pascal
if CaseEqual(name, 'pchar') or CaseEqual(name, 'pansichar') then
```
The compiler checks literally for `'pchar'` and `'pansichar'` to trigger the `ASTIVal[node] := -2` sentinel (which instructs the code generator to add the `+8` offset for string types). For custom aliases or any other pointer type names, it performs a raw pointer reinterpret cast, which skips the `+8` adjustment.

## Workaround

Use the built-in `PChar` type name for all casts of string values to C-style strings.

## Fix direction

The compiler should check if the target cast type resolved is a pointer to `Char`/`AnsiChar` (i.e. checking `LastTypePointerElemTk = tyChar`), rather than matching the type name literally against `'pchar'` or `'pansichar'`.

## Log
- 2026-06-20 — opened. Discovered in gtk3widgets.pas.

## DONE 2026-06-20

Fixed in parser.inc: the type-alias cast path now uses the `-2` PChar adapter
(skip the 8-byte length prefix for a string operand; plain reinterpret
otherwise) when the alias resolves to `^Char` (`AliasElemTk = tyChar`), instead
of a raw pointer reinterpret. `PC(s)` with `type PC = ^Char` now points at the
char data like `PChar(s)`. Non-Char aliases unchanged. Validated; self-host
byte-identical, make test green.

(Aside, pre-existing & unrelated: `writeln(p^)` on an alias-cast pointer whose
pointee is dereferenced directly can segfault — `PI(@n)^` with `type PI=^Integer`
crashes too, independent of this fix. Worth a separate ticket if it bites.)

**Resolved-in:** 71036f6 (finalizing commit)
