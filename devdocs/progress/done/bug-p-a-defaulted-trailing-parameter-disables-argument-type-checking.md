---
slug: bug-p-a-defaulted-trailing-parameter-disables-argument-type-checking
title: "A defaulted trailing parameter disables argument type checking on the arguments that WERE supplied"
track: P
prio: 90
type: bug
status: done
owner: frankS
found-by: frankS
created: 2026-09-17
resolved: 2026-09-17
tags: [overload-resolution, type-checking, default-arguments, memory-corruption, silent-wrong-value]
blocked-by: []
summary: "`function P(const c: AnsiString; k: Integer = 0)` called as `P(rec)` COMPILED and read the record's bytes as a string -- `Length(c)` = 17297991344808736. No overload needed, no set literal needed, no unusual type needed: ONE defaulted trailing parameter and any wrongly typed argument. `P(c: Integer; k: Integer = 0)` called with an AnsiString printed the string's address. fpc 3.2.2 refuses all of them. Cause: `TryFillTrailingDefaults` (pasparser_call.inc) selected its candidate on NAME and ARITY alone and never looked at the types of the arguments the caller DID write -- and it is a FALLBACK reached only after the ordinary match has refused, so it rescued precisely the calls that had just been type-rejected. The SAME call with the trailing argument written out was refused correctly, which is what says this is the sibling-spelling class and not a missing check. Fixed 2026-09-17 by gating candidate selection on `MatchParamAccepted` (the union predicate the free path itself refuses on) behind a fill of the argument side channels. INERT UNTIL THE NEXT PIN: `compiler/**`."
---

# A defaulted trailing parameter disables argument type checking

## Repro

```pascal
program w1;
type TR = record a: Integer; end;
function P(const c: AnsiString; k: Integer = 0): Integer;
begin P := Length(c); end;
var r: TR;
begin r.a := 1; WriteLn(P(r)); end.
```

| compiler | result |
| --- | --- |
| fpc 3.2.2 | `Error: Incompatible type for arg no. 1: Got "TR", expected "AnsiString"` |
| pxx, pin v410 (`c599e8546121`) | compiles, rc=0, **binary segfaults** |
| pxx, fixed | `no overload of P matches these arguments / argument types: (record)` |

Nothing here is exotic. There is no overload, no generic, no set literal, no
cross-target width question -- a single routine, one defaulted parameter, and an
argument of the wrong type.

## Why it survived

**The check was never missing. One of the two spellings of the same call was
not wired to it.** Written out, `P(r, 0)` is refused by pxx today and always
was; only the spelling that OMITS the defaulted argument reaches
`TryFillTrailingDefaults`, and that function's candidate scan asks two
questions -- does the name match, and does the arity fit once the tail is
defaulted -- and no third. This is
`normalise-dont-special-case.md`'s sibling rule in its stated form: *grep for
the OTHER SPELLING'S HANDLER, not for the feature*. Both spellings mean the
same thing to whoever wrote the source, so no test corpus separates them.

It is also **structurally invisible to the instrument that would catch it**:
the fallback runs only where the ordinary match has already refused, so the
population it rescues is exactly the population of calls with a type error in
them. A suite of correct programs cannot reach it.

## Measured boundary

All rows fpc 3.2.2 `-Mobjfpc` against pxx at the commit before the fix.

| argument | parameter | trailing default | pxx before | pxx after | fpc |
| --- | --- | --- | --- | --- | --- |
| `TR` record | `AnsiString` | yes | compiled, `1` | REFUSED | refused |
| `TR` record | `AnsiString` | **no** | REFUSED | REFUSED | refused |
| `AnsiString` | `Integer` | yes | compiled, `4265208` (an address) | REFUSED | refused |
| `['x']` set literal | `AnsiString` | yes | compiled, `Length` = 17297991344808736 | REFUSED | refused |
| `['x']` set literal | `AnsiString` | **no** | REFUSED | REFUSED | refused |
| record, in position **2** of 3 | `AnsiString` | yes | compiled | REFUSED | refused |
| `AnsiString`, in position **3** of 4 | `Integer` | yes | compiled | REFUSED | refused |

The two `no` rows are the control: same argument, same parameter, same
compiler, and the only thing that varies is whether the trailing default was
written out.

## Log

- 2026-09-17 | frankS | fixed and closed, commit `2de677672`. INERT UNTIL THE
  NEXT PIN: the change is `compiler/**`, so pin v410 (`c599e8546121`) still
  compiles every row in the table above.

## The fix

`TrailingDefaultArgsAcceptable` (pasparser_call.inc, beside
`FillMatchArgChannelsAt`), asked from the candidate scan. Three properties are
deliberate:

* **It asks `MatchParamAccepted`, the UNION of what `MatchProcCall`'s phases
  accept** -- not a stricter rule of its own. Anything this fallback refuses
  becomes "no overload matches", so a narrower predicate would convert working
  calls into diagnostics.
* **It fills the argument side channels first.** `MatchParamCompatible` reaches
  `MatchArgNilOk` and `MatchArgProcAddrOk`, and with the channels invalid both
  answer False -- which would refuse `CallsIt(@Sub)` against a procedural
  parameter and `TakesPtr(nil)` against a pointer one. Those two rows are in
  the positive test for exactly this reason and they fail differently from the
  rest of it. Unlike the method probe there is no rewind to schedule around:
  the argument list is fully parsed when this runs.
* **It abstains on `tyUnknown`** rather than refusing -- the sentinel for a
  type that was never settled, which is ordinary under NilPy and for a node
  downstream of an earlier error. Refusing there reports a type mismatch as the
  second diagnostic of one mistake.

One gate, three callers: the expression site (`pasparser_expr.inc`), the
statement site (`pasparser_stmt.inc`) and NilPy's (`pyparser.inc`). A check at
the call sites would have been three spellings of one rule.

## Tests

* `test/test_default_arg_typecheck_fail.pas` -- four shapes, refused at fpc's
  own four line numbers, rc=1, no binary written. **Positive control fires:**
  pin v410 compiles it and the binary segfaults.
* `test/test_default_arg_typecheck_positive.pas` -- 10/10 under fpc and pxx.
  Its job is the over-refusal direction: the procedural-address and `nil` rows
  are refused by a version of this fix that forgets the channel fill, and the
  two- and three-argument rows are passed by a gate that checks only argument 0.

## What this does NOT fix

`bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set` [55] is a
separate and still-open defect that this one was found underneath. With the
fallback no longer rescuing it, `P(['x'])` against an `AnsiString` /
`array of AnsiString` overload pair now selects **fpc's candidate** (the array
one) instead of the string one -- but the argument is still presented as a SET,
so the callee reads a garbage length. Selecting right and lowering wrong is one
defect where there were two; it is not a fix. See that ticket.
