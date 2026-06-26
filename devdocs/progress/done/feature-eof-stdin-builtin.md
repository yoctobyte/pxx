# `Eof` (standard input) not recognized

- **Type:** feature (compiler builtin / RTL — Track A)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21
- **Relation:** next `examples/chess` blocker after the bare-function-name
  result-var fix (c8ccc7b). Chess now parses to its REPL.

## Problem

`examples/chess/chess.pas:895` uses bare `Eof` to test standard input:

```pascal
while running do
begin
  write('chess> ');
  if Eof then Break;     { pascal26:895: error: undefined variable (Eof) }
  readln(line);
  ...
```

PXX does not recognize `Eof` (no-arg, standard input). `readln`/`writeln`/`read`
are compiler keyword-builtins (tkReadln, …); `Eof` has no such token and no RTL
symbol, so it resolves to nothing.

## Direction

- Simplest: a no-arg `Eof: Boolean` builtin/RTL routine that reports end-of-input
  on stdin (and ideally `Eof(f)` over a textfile, consistent with the textfile
  unit). Sibling of the `read`/`readln` builtins.
- **Track question:** an unrecognized identifier in expression position points at
  a missing builtin (Track A). But it is textfile/stdin I/O, which is Track B's
  lane (see the textfile unit work). Decide ownership before starting; if it is
  modelled as a textfile method on the implicit `Input`, it is Track B; if a
  bare-stdin intrinsic, Track A.

## Acceptance

- `if Eof then ...` over standard input compiles and behaves (true at end of
  piped input).
- `examples/chess` advances past `chess.pas:895` into its REPL loop.

## Resolution (2026-06-21, Track A)

Implemented as a no-arg special builtin (call id 210, like `Length`), x86-64
codegen — the same support level as `readln` (both x86-64-only; cross errors
gracefully with "builtin/special call not yet supported", no crash).

- Parser (`ParseFactor`): bare `Eof` / `Eof()` (no file arg) lowers to an
  `AN_CALL` with id -210, Boolean result. `Eof(f)` (a `(` + argument) still falls
  through to the textfile `Eof(var f: Text)` routine; `idx<0` lets a user variable
  named Eof win.
- Codegen (`EmitEof`, ir_codegen.inc): result in rax. Not-eof if the line buffer
  holds unparsed content (`pos < len`) or a pushed-back byte is held; else peek
  one byte from fd 0 — read ≤ 0 is EOF, a real byte is stashed in `BSS_PEEK_BYTE`
  / `BSS_PEEK_VALID` and reported not-eof.
- `EmitReadLine` consumes the pushed-back byte before reading, so the byte Eof
  peeked is not lost (verified: `x\ny` with no trailing newline reads `y` in
  full).

LANDMINE (cost a debug cycle): the BSS-allocation edit that added
`BSS_PEEK_VALID/BYTE` accidentally dropped the `BSS_LINE_LEN` line, so `len`
aliased another global (nonzero) → `pos<len` always true → Eof skipped its read
and readln segfaulted. Restored the allocation. When inserting BSS slots, do not
disturb the existing ones.

- Gate: make test green; default + --threadsafe self-host byte-identical. Tests:
  `test/test_eof_stdin.pas` (piped, incl. no-trailing-newline + empty input).
- chess: advances past `chess.pas:895`; next blocker is `eng.Free` — built-in
  TObject has no `Free` method (see `bug-method-call-free-tobject`, backlog).

## Log
- 2026-06-21 — filed (self-discovered as the next chess blocker after c8ccc7b).
- 2026-06-21 — implemented (special builtin 210 + pushback). Track A.
