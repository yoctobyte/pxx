---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: frankS
---

# `{$if declared(X)}` cannot see a used unit's declarations, and answers False rather than refusing

Measured 2026-09-06 at compiler `d697a8a680fd`. `uu1` declares
`TPlainUnit = class`; the program `uses uu1`, and in the same program:

    v := TPlainUnit.Create;              { works — the type is fully usable }
    {$if declared(TPlainUnit)} A = 1 {$else} A = 0 {$endif}

    pxx:  the type IS usable: TRUE   declared() says=0
    fpc:  the type IS usable: TRUE   declared() says=1

A local declaration in the same file answers True correctly, so the operator
works; what it cannot see is the other side of a `uses`.

## Cause, and why it is not a small fix

`PasCondNameDeclared` (paslexer.inc) answers by scanning
`Tokens[0..TokCount-1]`, and its own header states the model honestly: only
declarations *already emitted* are knowable. A used unit's tokens are appended
to that same stream by `LexAppend` — but from `pasparser_proc.inc:5745`, at
PARSE time. The order is: LexAll(main) → conditionals resolved → parse → `uses`
→ LexAppend(unit). Every conditional in the main file is decided before a single
unit token exists.

Closing it means resolving and lexing a used unit *during* the main LexAll —
unit search paths, per-unit directive state, and recursion, in shared lexer
territory. That is why this is filed rather than fixed.

## Why it ranks above a missing diagnostic

Feature detection across a unit boundary is what `declared()` is FOR. The
failure is silent and takes the `{$else}` arm, and the `sizeof` arm eleven lines
below it in the same file already says what that costs: *"a conditional that
takes the wrong branch does not produce a wrong value -- it produces a different
program."* That arm refuses a name it cannot size for exactly this reason.
`declared` answers False instead, which is indistinguishable from a correct
negative — and a correct negative is the common case, so nothing looks wrong.

Note the asymmetry deliberately: refusing is NOT obviously the right repair here,
because False is the correct answer for the case the header was written for
(Synapse's `Posix.StrOpts.*` under a profile with no such unit). Whoever fixes
this has to separate "not declared" from "declared somewhere I cannot see yet",
and today the scan cannot tell those apart.

## The generic-arity half, measured while here

`tgeneric93.pp` needs this AND the arity spelling. Both halves measured:

| form | pxx | fpc |
| --- | --- | --- |
| `declared(TDel)` where only `TDel<T>` exists, delphi mode | True | **False** |
| `declared(TFpc)` where only `generic TFpc<T,S>` exists, objfpc | False | False |

The objfpc row agrees for the wrong reason: `generic` is a plain `tkIdent`
here (there is no `tkGeneric`), so it consumes the scanner's `expectName` slot
and `TFpc` is never examined at all. Any arity work must handle that first or it
will answer False for every objfpc generic while looking correct on this row.

The arity spelling itself is otherwise cheap: `<>` = 1 param, `<,>` = 2,
`<,,>` = 3; peek from the matched name token for `tkLt`, count commas at depth 1
to the matching `tkGt`, and keep scanning on an arity mismatch rather than
returning on the first name hit — `TTestDelphi<T>` and `TTestDelphi<T,S,R>` are
two declarations of one name, and pxx already supports that overloading (all
four of `TA<T>` / `TA<T,S,R>` / `TB` / `TB<T,S>` construct correctly today).
None of it helps tgeneric93 until the unit half lands: every name that row
probes lives in `ugeneric93a` / `ugeneric93b`.

Changing the bare form to require arity 0 is a behaviour change for any existing
`declared(SomeGeneric)`; grep before landing it.
