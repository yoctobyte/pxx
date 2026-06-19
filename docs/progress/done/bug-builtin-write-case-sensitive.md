# Builtin write/writeln matched case-sensitively (only lowercase resolves)

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (discovered by Claude B: examples/adventure)

## Symptom

User-defined identifiers are case-insensitive (the documented default — see
`defs.inc:610` "standard case-insensitive Pascal"; `FOO` resolves to `Foo`). But
the builtin I/O intrinsics only match the exact lowercase spelling:

```
writeln;        -> OK
WriteLn;        -> pascal26: error: undefined variable (WriteLn)
Writeln(7);     -> pascal26: error: undefined variable (Writeln)
WRITELN(7);     -> pascal26: error: undefined variable (WRITELN)
```

`examples/adventure/engine.pas:228` (`WriteLn;`) fails for this reason. Likely
affects `write` / `read` / `readln` too, and possibly other intrinsics matched
by a hardcoded lowercase string compare rather than the case-insensitive symbol
path.

## Impact

Blocks any FPC-idiomatic demo that uses mixed-case `Write`/`WriteLn`/`ReadLn`
(common in real Pascal). Track B cannot fix from `lib/**` — the intrinsics are
recognized in the compiler, not the RTL.

## Direction

Resolve builtin intrinsic names through the same case-insensitive matcher used
for ordinary identifiers (respecting `CaseSensitiveMode` when the
`{$CASESENSITIVE ON}` directive is active). Add a test covering
`WriteLn` / `Write` / `ReadLn` mixed case.

## Log
- 2026-06-19 — opened by track B while advancing the adventure demo (after
  IntToStr + Copy/Trim landed, this is the next blocker before the Text-file I/O
  gap).

## Resolution (2026-06-19) — DONE (commit 3de5d05)

The four I/O intrinsics (Write/WriteLn/Read/ReadLn) now match case-insensitively
in the lexer (via CaseEqual) unless {$CASESENSITIVE ON}, where the exact
lowercase spelling still applies. No mixed-case Write/Read identifiers exist in
the compiler source (verified) so self-host stays byte-identical. test_case_io in
test-core.
