---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
found-by: frankS
created: 2026-09-09
summary: "A forward pointer declared inside a class's nested `type` section is never resolved: `TFactory = class private type PPRec = ^PRec; PRec = ^TRec; TRec = packed record ... end;` answers `forward type not resolved: PRec is used as the target of a ^ and is never declared as a type`, pointing at the FIRST line while the target is declared on the next one. fpc 3.2.2 compiles it and prints 7. PRE-EXISTING, not new: refused identically by pin v407 and by HEAD 4d1b041a7fc9, in BOTH objfpc and delphi mode, and as a program and as a unit -- four spellings, one answer. This is the LATENT half of the rtl-generics regression bisected to ad7c03b03: the corpus hits this exact construct at generics.defaults.pas:224 and used to get through it, so that commit stopped whatever was carrying the corpus case rather than breaking forward types outright. The two are filed separately on purpose -- see [[bug-p-the-generics-corpus-wall-moved-backward-from-2729-to-224]] for the regression."
---

# The repro — refused by pin and HEAD alike, compiled by fpc

```pascal
program fwd;
{$mode objfpc}
type
  TFactory = class
  private type
    PPRec = ^PRec;      { <- reported here }
    PRec  = ^TRec;      { <- declared here }
    TRec  = packed record a: LongInt; end;
  public
    class function Go: LongInt; static;
  end;
class function TFactory.Go: LongInt;
var r: TRec; p: PRec; pp: PPRec;
begin r.a := 7; p := @r; pp := @p; Result := pp^^.a; end;
begin WriteLn('fwd ', TFactory.Go); end.
```

`fpc -Mobjfpc` prints `fwd 7`. pxx: `forward type not resolved: PRec`.

Measured across four spellings, all refused, so none of them is the boundary:
objfpc and delphi mode; as a program and as a unit interface. Pin v407 and HEAD
`4d1b041a7fc9` give the identical message, so this is not today's regression.

## Why it is filed apart from the regression it explains

The rtl-generics corpus contains this construct at `generics.defaults.pas:224`
and **used to compile past it** — the wall was at 2729 until `ad7c03b03`. So the
corpus case was being carried by something that commit removed. Fixing the
latent bug here would make the corpus immune to that, but the two questions are
different and only this one has a repro that stands on its own.

**Do not start debugging at the reported line.** The check is deferred:
truncating the corpus unit at line 236 and compiling it parses the same block
cleanly on both compilers. The line in the message is where the unresolved name
was USED, not where the failure is decided.
