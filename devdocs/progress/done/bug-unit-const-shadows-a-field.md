---
track: A
prio: 60
type: bug
---

# A unit-level CONST shadows a same-named FIELD inside the class's own method

Pre-existing (reproduces on `stable_linux_amd64/default/pinned`), and it is a
plain-Pascal bug — NilPy only made it easy to hit:

```pascal
program fz2;
const S = 4;                       { any unit-level const with this name }
type
  ZBox = class
    s: AnsiString;
    constructor Create(const v: AnsiString);
    function firstIsA: Boolean;
  end;
constructor ZBox.Create(const v: AnsiString);
begin
  s := v;                          { -> "cannot assign to constant" }
end;
function ZBox.firstIsA: Boolean;
begin
  if s[1] = 'a' then firstIsA := True;   { -> "unexpected token" at the '[' }
end;
```

Inside a method, the class's own field must beat a unit-level name; only a
genuine local or parameter shadows it (FPC's scope order — and the class-CONST
path in `ParseLValueAST` already implements exactly that rule, with a comment
saying so). Bare fields do not: they are resolved only when nothing else bound
the name at all (`if idx < 0 then ... FindUField(...)`).

## How it shows up in practice

`lib/rtl/re.pas` exports Python's DOTALL flag as `S = 4`, names are
case-insensitive, and `lib/rtl/pathlib.pas`'s `Path` keeps its text in a field
called `s`. So `uses re, pathlib` — or, in NilPy, `import re` plus
`from pathlib import Path`, which is what songformatter's `convertrawtext.py`
writes — breaks pathlib from the inside. It is not specific to those two: any
one-letter or common-word const in any unit can capture a field elsewhere.

## What a fix has to cover (both sides, or neither)

An attempt that changed only `ParseLValueAST` made the ASSIGNMENT resolve to the
field while an EXPRESSION read still took the const — reads and writes
disagreeing is worse than a uniform error, so it was reverted. The bare-name
resolution in the expression path needs the same rule at the same time.

## Gate

`make test` + the repro above as a regression test, plus a Pascal case pairing
`uses re` with a class whose field is called `s`.

## Log
- 2026-07-28 — resolved, commit c3ad992a.
