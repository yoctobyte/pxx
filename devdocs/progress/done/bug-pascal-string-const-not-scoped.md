---
prio: 55
---

# bug: untyped string constants are not SCOPED — a method's local const leaks to every later routine

- **Track:** P (Pascal frontend)
- **Found:** 2026-07-13, while fixing b313 (fcl-json corpus). b313 guards the SYMPTOM; this
  is the underlying defect and is deliberately left open.

## What

The untyped-string-constant table (`FindStrConst` / `StrConstSOff` / `StrConstSLen`) is
FLAT. A constant declared inside a routine:

```pascal
function A: string;
const
  S = 'A string';      { LOCAL to A -- Pascal says it is invisible outside A }
begin
  A := S;
end;
```

stays visible to every routine parsed AFTER it. So a later routine sees `S` as that
constant even though it went out of scope at A's `end`.

## Why b313 is not the fix

b313 makes a VARIABLE in scope win over a same-named constant (Pascal's innermost-wins
rule), which is what fcl-json's testjsondata.pp needed — a `const S` in one method and a
`var S : TJSONString` in a later one. But a leaked constant still wins over:

- a constant of the same name declared in ANOTHER routine (the later one should shadow it,
  and if the two differ, the wrong text is substituted — SILENTLY),
- nothing at all: a routine that uses `S` with no declaration in scope should be an
  "unknown identifier" error, and instead quietly compiles against the leaked text.

Both are silent-wrong-behaviour, not diagnostics gaps, so this is a `bug-`, not a `compat-`.

## Repro (the second form — a leaked const shadowing a later const)

```pascal
program leak;
function A: string;
const S = 'first';
begin A := S; end;

function B: string;
const S = 'second';
begin B := S; end;

function C: string;      { S is NOT in scope here -- must be an error }
begin C := S; end;
begin writeln(A); writeln(B); writeln(C); end.
```

FPC: rejects C ("Identifier not found"). Check what pxx does with B and C.

## Where

`compiler/parser.inc`, `FindStrConst` and the const-declaration parser. The table needs a
scope/owner column (the `CurProc` that declared it, 0 = unit/global) and `FindStrConst`
must search innermost-first and skip entries owned by a routine that is not the current one
(or an enclosing one, for nested routines). Mirrors what the symbol table already does.

## Log
- 2026-07-13 — resolved, commit 3abe6150.
