# Capital `Write`/`WriteLn` rejected in some contexts (compiler self-build), works standalone

- **Type:** bug (compiler / intrinsic name resolution) — Track A
- **Status:** done
- **Owner:** Codex
- **Found / Opened:** 2026-06-27, while adding `--dump-cpp` to `compiler.pas`.
- **Relation:** residual gap after [[bug-builtin-write-case-sensitive]] (marked
  done) — that fix made capital write/writeln resolve in normal programs, but a
  context-dependent hole remains.

## Symptom

Adding `if DumpCpp then begin Write(Source); Halt(0); end;` to `compiler.pas`
(Source: AnsiString) failed the self-build:

```text
pascal26:64157: error: undefined variable (Write)
```

Lowercasing to `write(Source)` compiled fine. **Only the capitalization changed.**

But the *same* compiler binary accepts capital `Write`/`WriteLn` in a standalone
program:

```pascal
program wcase;
var s: AnsiString;
begin
  s := 'hi';
  Write(s); WriteLn('!');   { works: prints hi! }
  write('lower ok'); writeln;
end.
```

So capital write/writeln resolves in a small program but **not** in
`compiler.pas`. Same binary, opposite result → context-dependent.

## Open question (the crux)

Why does it differ by context? Candidates to check:
- The declaration **pre-scan** (compiler.pas is a large two-pass program;
  wcase.pas is trivial) — does prescan change how a `tkIdent`-spelled `Write`
  falls back to the write intrinsic?
- A near-miss symbol: the compiler source has `WriteExprIsFloat`,
  `writeShdr64`, etc. Case-insensitive resolution of `Write` shouldn't match
  those (different names), but worth confirming the resolver isn't doing a
  prefix/partial match or being shadowed by a `write`-spelled enum/const.
- Statement position / nesting depth in the big `else if isC then …` chain.
- Whether the lexer only emits the write/writeln intrinsic token for the exact
  lowercase spelling, and capital `Write` always goes through the
  symbol-resolution fallback (which the standalone case happens to satisfy and
  the self-build does not).

## Repro

- Self-build: temporarily put `Write(...)` (capital) in `compiler.pas` and
  rebuild → fails. (Reverted; the shipped `--dump-cpp` uses lowercase `write`.)
- Need a *minimal* program that reproduces the capital-Write rejection outside
  compiler.pas — wcase.pas above does NOT, so the trigger is still unknown.

## Acceptance

- Capital `Write`/`WriteLn`/`Read`/`ReadLn` resolve to the intrinsic in **all**
  contexts (statement + the compiler's own source), matching the documented
  case-insensitive default.
- A minimal repro added to `test/`.
- self-host byte-identical (the fix is name-resolution only).

## Log

- 2026-06-29 - Fixed by making only the four I/O intrinsic keyword matches
  (`Read`, `ReadLn`, `Write`, `WriteLn`) case-insensitive even while
  `{$CASESENSITIVE ON}` is active. Verified the original temporary
  `Write(Source)` self-build repro now succeeds, added a casesensitive-mode
  Read/Write regression, and `make test-core` passes.
- 2026-06-29 - Picked up on Track A. Reproduced the current compiler failing
  when `compiler.pas` temporarily changes the `--dump-cpp` branch from
  `write(Source)` to `Write(Source)`: `undefined variable (Write)`.
- 2026-06-27 - Found adding `--dump-cpp`. Capital `Write` rejected in
  compiler.pas, accepted standalone — same binary. Mechanism unknown; filed.
