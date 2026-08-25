---
slug: feature-p-fpc-global-operator-overload-declarations
track: P
prio: 72
type: feature
blocked-by: []
summary: "`operator := (const u:qword):Tconstexprint;` — FPC's UNIT-SCOPE operator overload declaration — is not parsed. It is the first wall behind the FPC-compiler define profile: constexp.pas:58, and constexp is what cutils and cstreams pull in first."
status: backlog
---

# FPC global (unit-scope) `operator` overload declarations

Found 2026-08-21 immediately behind
[[feature-mimic-fpc-compiler-define-profile]], which cleared
`{$i fpcdefs.inc}`. This is the next wall on the `cutils` / `cstreams` path.

## Repro

```pascal
{ FPC 3.2.2 compiler/constexp.pas, lines 58-62 }
operator := (const u:qword):Tconstexprint;inline;
operator := (const s:int64):Tconstexprint;inline;
operator := (const c:Tconstexprint):qword;
operator := (const c:Tconstexprint):int64;
operator := (const c:Tconstexprint):bestreal;
```

```
$ pascal26 --mimic-fpc-compiler p_cutils.pas
Expected: =, but got:  (Kind: 75, Line: 360)
pascal26:360: error: unexpected token
  near:   const u  qword >>>   Tconstexprint
```

(The line number is wrong — the token is `constexp.pas:58`. That is a separate
finding, [[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]].)

## What it is

FPC's `{$mode objfpc}` operator overloading at **unit scope**, not inside a
class: `operator <op> (params) : result;` with an implementation later in the
unit. `:=` is the implicit-conversion operator, which is how `Tconstexprint`
(FPC's compiler-wide "constant expression integer" record, holding either an
int64 or a qword plus an overflow flag) is assignable from and to plain
integers throughout the FPC compiler.

pxx already knows the CONCEPT — `--strict-operator` exists and the dialect has
operator overloading — so the gap is likely the unit-scope declaration form and
the `:=` operator name rather than overloading itself. Confirm before scoping.

## Why it matters beyond FPC

`operator :=` implicit conversion is how a Pascal library gives a record value
semantics against builtin types. Any real FPC corpus that wraps a scalar in a
record for range/overflow tracking hits this, so it is not FPC-compiler-specific
surface.

## Gate

`constexp.pas` parses; `cutils.pas` and `cstreams.pas` get past it under
`--mimic-fpc-compiler`. Plus the Pascal suite green and self-host
byte-identical. Cross-target breadth is Track T's.
