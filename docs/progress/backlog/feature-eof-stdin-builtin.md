# `Eof` (standard input) not recognized

- **Type:** feature (compiler builtin / RTL — likely Track A)
- **Status:** backlog
- **Owner:** —
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

## Log
- 2026-06-21 — filed (self-discovered as the next chess blocker after c8ccc7b).
