# AnsiString concat expression as a call argument allocates an ~8 MB static buffer per site

- **Type:** bug (Track A — codegen / managed-string temporaries)
- **Status:** DONE — 2026-06-23.
- **Owner:** —
- **Opened:** 2026-06-23 (found building the `screen` TUI lib, Track B)

## Symptom

Passing a **concatenation expression** of `AnsiString` directly as a function
argument makes the compiler reserve a fixed **~8 MB static (BSS) scratch buffer
per call site**. N such call sites => N × 8 MB of BSS. A 18-call test produced a
**151 MB** BSS segment.

Confirmed orthogonal to `const`/value and to the concat itself — it is the
concat-temp-as-argument specifically:

| argument form (param `const`/value AnsiString) | BSS (3 calls) |
|---|---|
| `F('' + #27 + '[A')` concat expr, `const` param | 25 MB (~8 MB/call) |
| `F('' + #27 + '[A')` concat expr, value param | 25 MB (~8 MB/call) |
| `F('abc')` plain string literal | ~4 KB (fine) |
| `v := '' + #27 + '[A'; F(v)` via a variable | ~4 KB (fine) |

So: a plain literal or a variable argument is fine; only a **concat expression
materialised as the argument temporary** triggers the giant static buffer.

## Minimal repro

```pascal
program z;
function F(const s: AnsiString): Integer; begin F := Length(s); end;
var t: Integer;
begin
  t := 0;
  t := t + F('' + #27 + '[A');   { each such site adds ~8 MB BSS }
  t := t + F('' + #27 + '[B');
  writeln(t);
end.
```

`pascal26 z.pas /tmp/z` reports `bss=16785696B` (~16 MB for 2 sites);
`readelf -S` shows the bloat is `.bss`. The same code with `v := '' + #27 + '[A';
F(v)` reports a normal ~4 KB BSS.

## Likely cause

The argument temporary for an `AnsiString` concat result appears to be backed by
a **per-site static scratch buffer with a hardcoded large capacity (~8 MB)**,
rather than a small/heap-managed temporary. Look at how a concat expression used
in argument position is lowered (the managed-string temp allocation for call
arguments) vs. the assignment-to-variable path, which is fine.

## Impact

BSS is zero-filled and lazily paged, so programs still run — but any lib/test
that passes concatenated strings to functions balloons its image to tens/hundreds
of MB. Found while writing `test/lib_screen.pas` (key-decoder asserts called
`ScreenDecodeKey('' + #27 + '[A')`): the test binary hit a 142 MB BSS. The
`screen`/`ansiterm` libraries themselves do NOT trip it (they build into a
variable first); the test was rewritten to assign the sequence to a var, which is
idiomatic anyway. No library code bent around this.

## Acceptance

- A concat expression passed as an `AnsiString` argument uses a normal
  small/heap temporary; the repro's BSS is ~KB, not ~8 MB/site.
- Self-host fixedpoint + existing string tests stay green.

## Fix log

- 2026-06-23 — DONE (46666a2). Root cause: a frozen `tyString` symbol at GLOBAL scope
  (`CurProc < 0`) was sized `STRING_CAP` (8 MB) in AllocVar (symtab.inc ~1495);
  proc-locals already used `LOCAL_STR_CAP` (256). A concat result materialised as
  a call argument in the MAIN body is a HIDDEN temp (name `''`) at global scope,
  so it got the full 8 MB — per site. Fix: only NAMED global frozen strings keep
  `STRING_CAP`; hidden temps (`name = ''`) use `LOCAL_STR_CAP + 8` like the same
  temp inside a procedure. Repro BSS 16 MB -> 4768 B; output unchanged. Named
  global string vars and the compiler's own buffers are untouched (self-host
  byte-identical, no reseed). Test `test/test_concat_arg_bss.pas` + a Makefile
  BSS-size guard (fails if any `bss=` >= 7 digits). make test + cross-bootstrap
  green.
