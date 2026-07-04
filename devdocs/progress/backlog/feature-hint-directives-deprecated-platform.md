# Hint directives (`deprecated` / `platform` / `experimental` / …) on const/type/proc

- **Type:** feature (parser — FPC-compat dialect, Track A)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-04 (isolating the `fgl` "generics" wall — it was NOT
  generics; see [[fpc-lcl-compile-probe]])

## Problem

FPC hint directives — `deprecated ['msg']`, `platform`, `experimental`,
`unimplemented`, `library` — are accepted after a const value, a type
declaration, and in a routine's modifier list. pxx rejects them:

```pascal
const  MaxN = 1024 deprecated;                    { pascal26: unexpected token }
type   TOld = Integer deprecated;                 { unexpected token }
procedure P; deprecated; begin end;              { unexpected token }
procedure Q; deprecated 'use R instead'; begin end;
```

(`var x: Integer deprecated;` happens to already pass.) This is pervasive in real
FPC RTL/FCL source — e.g. `fgl.pp`'s `MaxGListSize = MaxInt div 1024 deprecated;`
desyncs the parser and the error surfaces ~15 lines later as a misleading
`expected name`, which read as a "generics" failure but is not.

## Isolated repros

```
const K = 5 deprecated;          -> unexpected token
const K = 5 platform;            -> unexpected token
type  T = Integer deprecated;    -> unexpected token
procedure P; deprecated; ...     -> unexpected token
```

## Fix (Track A, parser.inc)

Add a shared `SkipHintDirectives` that consumes a run of the hint words, where
`deprecated` may be followed by an optional string message, then wire it at:

- **Const section** — `ParseConstSection` (~parser.inc:11100): after the const
  value, before the terminating `;` (both typed and untyped const forms).
- **Type section** — `ParseTypeSection` (~parser.inc:11752): after the type, before
  the `;`.
- **Routine modifiers** — the modifier lists that already handle
  `inline`/`register`/`cdecl`/… : the pre-scan skip loop (~parser.inc:13610) AND
  the real parse in `ParseSubroutine` (~parser.inc:13870+ modifier handling).

Semantics: parse-and-ignore is acceptable for v1 (no deprecation warning). A
follow-up could emit `warning: symbol 'X' is deprecated` at use sites, but merely
accepting the syntax is what unblocks compiling FPC source.

## Acceptance

- The four isolated repros compile.
- `fgl.pp` no longer walls on the `deprecated` const (it advances to the next,
  separate gap — see [[feature-sizeof-const-intrinsic-in-const-eval]] and the
  `uses types` dependency).
- Self-host byte-identical; `make test` green; a regression `.pas` exercising a
  hint directive on const/type/proc.
