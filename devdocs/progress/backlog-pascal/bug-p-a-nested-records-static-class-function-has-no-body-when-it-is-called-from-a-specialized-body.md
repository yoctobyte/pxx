---
track: P
prio: 60
type: bug
blocked-by: []
status: open
owner: frankS
summary: "A static class function of a class-nested RECORD gets no body when the CALL comes from a specialized generic body: `unresolved forward: TInst.Mk` from ApplyCallFixups (symtab.inc), i.e. a call fixup whose Procs[].BodyAddr is still -1, raised while linking builtinheap so the message blames the appended unit. 30-line repro; fpc 3.2.2 -Mdelphi compiles and runs it. TWO CONTROLS, both measured 2026-09-09 at binary f22102f66298: make the CALLER non-generic and it compiles and runs; make the nested type a CLASS instead of a RECORD and it compiles. Qualifying the call (`TSvc.TInst.Mk` rather than the inherited-name `TInst.Mk`) does NOT help, and the caller need not descend from the nested type's owner. This is the `uses Generics.Defaults` wall on the rtl-generics rung: generics.defaults.pas declares `TComparerService.TInstance` with two static class functions and calls them 62 times from `class constructor THashService<T>.Create`. BOTH are broken there, not just the reported one -- `Error` aborts at the FIRST failing fixup, so commenting out the 25 CreateSelector call sites moves the message to `TInstance.Create`. Do not read the reported name as the only one."
---

# A nested record's static class function has no body when the call is in a specialized body

**Blocks [[feature-pascal-corpus-generics]]** — this is the `uses Generics.Defaults`
wall, at binary `f22102f66298`.

## The repro — fpc 3.2.2 `-Mdelphi` prints `ok`, pxx refuses

```pascal
program inner3;
{$mode delphi}
type
  TSvc = class
  public type
    TInst = record
      P: Pointer;
      class function Mk(A: Pointer): TSvc.TInst; static;
    end;
  end;

  THash<T> = class(TSvc)
    class function Get: TSvc.TInst; static;
  end;

class function TSvc.TInst.Mk(A: Pointer): TSvc.TInst;
begin
  Result.P := A;
end;

class function THash<T>.Get: TSvc.TInst;
begin
  Result := TInst.Mk(nil);
end;

var r: TSvc.TInst;
begin
  r := THash<Integer>.Get;
  if r.P = nil then WriteLn('ok');
end.
```

```
pascal26:2: error: unresolved forward: TInst.Mk
  in: ./compiler/builtin/builtinheap.pas
```

**The message names the wrong file and says so itself.** It comes from
`ApplyCallFixups` (`symtab.inc`), which raises on the first fixup whose
`Procs[procIdx].BodyAddr` is still `-1` — reached while linking the appended
builtin unit, long after the offending call was parsed. The proc ROW exists
(from the declaration) and no BODY ever reached it.

## Controls, and each one removes a suspect

| variation | result |
| --- | --- |
| caller `THash = class(TSvc)`, non-generic | **compiles, prints `ok`** |
| nested type is a `class`, not a `record` | **compiles** |
| call written `TSvc.TInst.Mk(nil)` (fully qualified) | still refuses |
| `THash<T> = class` (no kinship with TSvc), qualified call | still refuses |

So it is neither the inherited unqualified spelling nor the descent: the
discriminators are **specialized caller** and **record**. The implementation
body IS parsed — a deliberate syntax error placed inside it is reported
normally — so this is a binding failure, not a parse one. **Which of the two
rows is the duplicate — the one the declaration made or the one the call from
the specialized body resolved to — is NOT measured yet.** That is the first
question for whoever takes it.

## On the corpus

`generics.defaults.pas` declares `TComparerService.TInstance` (`:349`) with
`Create` (`:350`) and `CreateSelector` (`:351`), both `static`, implemented at
`:2179` and `:2186`, and calls them 37 + 25 times from
`class constructor THashService<T>.Create` (`:2296`).

**Both are broken and the readout shows one.** `Error` aborts at the first
failing fixup, so `CreateSelector` is reported and `Create` is not; comment out
the 25 `CreateSelector` call sites and the message becomes
`unresolved forward: TInstance.Create`. An earlier reading of mine — "`Create`
binds fine, so the two differ" — was that abort, not a difference, and renaming,
re-typing (`CodePointer` -> `Pointer`) and re-arity-ing `CreateSelector` all
change nothing.
