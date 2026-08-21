---
slug: feature-p-fpc-assigned-enum-ordinals-with-colon-equals
track: P
prio: 40
type: feature
blocked-by: []
summary: "An enum with explicit ordinals written FPC-style — `(ms_on := 1, ms_off := 2)` — is refused. objfpc mode spells assigned enum values with `:=` where Delphi mode uses `=`; pxx accepts only the Delphi spelling. Second wall behind the FPC-compiler define profile: globtype.pas:800, which cclasses pulls in."
status: backlog
---

# FPC `{$mode objfpc}` assigned-enum ordinals use `:=`, not `=`

Found 2026-08-21 immediately behind
[[feature-mimic-fpc-compiler-define-profile]]. This is the wall on the
`cclasses` / `globtype` path — the sibling of
[[feature-p-fpc-global-operator-overload-declarations]], which is the wall on
the `cutils` path.

## Repro

```pascal
{ FPC 3.2.2 compiler/globtype.pas, line 800 }
tmsgstate = (
  ms_on := 1,
  ms_off := 2,
  ms_error := 3,
  ...
);
```

```
$ pascal26 --mimic-fpc-compiler p_cclasses.pas
Expected: ), but got:  (Kind: 63, Line: 1103)
pascal26:1103: error: unexpected token
  near:  type tmsgstate   ms_on >>>
```

(Line 1103 does not exist in globtype.pas, which is 843 lines — see
[[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]].)

## What it is

Assigning explicit ordinals to enum members. **The spelling differs by mode**,
which is the whole of this ticket:

| mode | spelling |
| --- | --- |
| Delphi / `{$mode delphi}` | `(ms_on = 1, ms_off = 2)` |
| **objfpc / `{$mode objfpc}`** | `(ms_on := 1, ms_off := 2)` |

pxx accepts the `=` form (the error is "Expected: )", i.e. it parsed the
identifier and then wanted the list to end). So this is one token in one place,
not a feature — the enum machinery behind it already exists.

Worth checking while there whether the two spellings should BOTH be accepted
unconditionally or whether the `:=` form belongs behind `-Mobjfpc`. pxx's
dialect is deliberately lax by default and FPC-parity strictness lives behind
per-feature flags, which argues for accepting both always — but that is the
call to state in the ticket rather than assume. See
`devdocs/dev/normalise-dont-special-case.md`: two spellings of one concept want
one path, not a second one.

## Gate

`globtype.pas` parses; `cclasses.pas` gets past it under
`--mimic-fpc-compiler`. Pascal suite green + self-host byte-identical.
