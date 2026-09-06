---
track: B
prio: 40
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`lib/rtl/sysutils.pas` does not declare `CharInSet`. It declares TSysCharSet and its own comment calls that type 'the parameter type of the CharInSet / character' -- so the type is there, named for the function, and the function is not. FPC's is `function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean;`, and it exists because Delphi-compatible code cannot write `Ch in Set` when Ch is a WideChar; real code uses it unconditionally. fcl-passrc pparser.pp:559 is the live case (`while (WStart<=Length(S)) and charinset(S[WStart],WhiteSpace)`), and it is currently INVISIBLE -- it sits behind earlier parse walls, and was only found by truncating the unit until the parse succeeded and the semantic pass could reach it. Blocks fcl-passrc rung 7 pparser.pp behind the parse walls."
---

# sysutils.CharInSet

- **Type:** feature (compat — FPC/Delphi RTL function absent) — **Track B**
  (`lib/rtl/sysutils.pas`).

```pascal
function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean;
begin
  Result := Ch in CSet;
end;
```

The one-line body is the whole function in FPC too; it exists for the Delphi
`WideChar` overload's sake, not for the AnsiChar one.

## Why it is filed rather than fixed on the spot

Found by Track P while cutting `pparser.pp` down to localise a parse error — it
is behind two parse walls and cannot be reached by compiling the unit today, so
**nothing here has been measured end-to-end**. The declaration is trivial; what
is not established is whether pxx's `TSysCharSet` and its `in` operator accept
this exact shape, and a one-line addition that compiles is not evidence the call
site works. Whoever takes it should drive it from a program, not build it.

## Gate

Assert a value on BOTH answers — `CharInSet('A', ['A'..'Z'])` true and
`CharInSet('a', ['A'..'Z'])` false. A predicate that returns a constant passes a
one-row test, and the failure mode here (an empty or mis-built set) is exactly
the one that returns the same answer for every character.
