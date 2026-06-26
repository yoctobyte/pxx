# FPC bootstrap: GetTokenStrFromRaw used in lexer.inc before its parser.inc definition
- **Status:** DONE (2026-06-26, Track A, pin v81)

- **Type:** bug (Track A — shared lexer/parser include-order; FPC single-pass
  compliance). Surfaced on `feat/cfront`.
- **Found:** 2026-06-26 during the cfront→master merge prep, after deduping the
  token enum (`defs.inc`). With the dup gone, `make bootstrap` (FPC) reveals the
  next single-pass error.

## Symptom
```
lexer.inc(1921,24) Error: Identifier not found "GetTokenStrFromRaw"
compiler.pas(531) Fatal: There were 1 errors compiling module, stopping
```
`make bootstrap` / `make test-fpc` (the FPC paths) fail. The FPC-free daily gate
(`make test`, self-host off the pinned stable) and the merge self-host are
**unaffected** — the pxx self-host compiler is whole-program / lenient, so it
resolves the later definition fine. This blocks only FPC cold-start + release
compliance (`fpc-check`, `test-asm-emit`).

## Cause
`GetTokenStrFromRaw` is defined at `parser.inc:414`. `compiler.pas` includes
`lexer.inc` (line 30) **before** `parser.inc`, but branch commit `cd30d0c4`
(`feat(compiler): readable 'near:' source context on unexpected-token errors`)
added a call to it at `lexer.inc:1921`:
```pascal
ctx := ctx + GetTokenStrFromRaw(Tokens[ei-1].SOffset, Tokens[ei-1].SLen) + ' ';
```
FPC compiles top-to-bottom in one pass, so the identifier is not yet visible.
(The use is branch-only — `origin/master` `lexer.inc:1921` does not call it.)

## Fix options (Track A pick)
1. Add a `forward;` declaration of `GetTokenStrFromRaw` before `lexer.inc` is
   included (smallest; an interface-style prototype block).
2. Move `GetTokenStrFromRaw` (a pure TokChars-pool accessor) to a low include
   that precedes `lexer.inc` (e.g. into `lexer.inc` itself near the pool, or a
   shared early helper unit).
3. Inline the pool read at the `lexer.inc:1921` call site.

Self-host stays byte-identical either way (resolution-only, no codegen change),
so no reseed beyond the normal pin.

## Acceptance
`make bootstrap` and `make test-fpc` compile clean; self-host still
byte-identical.

## Resolution (2026-06-26, Track A)
Moved `GetTokenStrFromRaw` from parser.inc to lexer.inc (after AppendChar, outside the FPC/pxx ifdef), ahead of its lexer.inc diagnostic use and the parser.inc uses. FPC cold-start (`make bootstrap`) and self-host both green; behaviour-neutral; re-pinned v81.
