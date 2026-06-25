# bug: arm32 `writeln(LongWord)` mangles a value with the high bit set

- **Type:** bug (codegen — arm32 unsigned-32 write formatting)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track A, verifying bug-not-on-int64-is-boolean
  (`test_not_int64_expr` LongWord lines) on arm32.

## Symptom

On **arm32**, `writeln` of a `LongWord`/`Cardinal` (32-bit unsigned) whose value
has bit 31 set prints garbage; small values are fine. x86-64 / i386 / aarch64 are
all correct.

```pascal
var c: LongWord;
begin
  c := 4294967295; writeln(c);   { arm32 prints `/`   ; want 4294967295 }
  c := 100;        writeln(c);   { arm32 prints 100   (OK)             }
end.
```

Independent of `not` — a plain assignment + writeln reproduces it. The bitwise
`not` work only surfaced it (`not LongWord(0)` = 4294967295).

## Likely cause

arm32's unsigned-32 write path (the `writeln`/`Str` integer formatter for
`tyUInt32`) probably treats the value as signed, or the high-bit value collapses
to a wrong digit/char — `/` is ASCII 47, suggesting a single mis-derived digit
rather than a full number. Compare with the i386/aarch64 unsigned-write paths,
which handle the same value correctly (so the fix is arm32-local).

## Workaround

`test_not_int64_expr.pas` checks the LongWord complement by value comparison
(`if c = 4294967295`) instead of `writeln(c)`, so it stays portable across
targets. Remove the workaround once this is fixed.

## Acceptance

- `writeln(c)` for `c: LongWord` with bit 31 set prints the correct unsigned
  decimal on arm32 (matching the x86-64 oracle).
- Regression test (cross compare arm32 vs x86-64).
