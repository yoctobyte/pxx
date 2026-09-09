---
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: frankS
summary: "FIXED (see below). A static class function of a RECORD -- nested or top-level -- got no body when the CALL came from a specialized generic body: `unresolved forward: TInst.Mk` from ApplyCallFixups (symtab.inc), i.e. a call fixup whose Procs[].BodyAddr is still -1, raised while linking builtinheap so the message blames the appended unit. 30-line repro; fpc 3.2.2 -Mdelphi compiles and runs it. TWO CONTROLS, both measured 2026-09-09 at binary f22102f66298: make the CALLER non-generic and it compiles and runs; make the nested type a CLASS instead of a RECORD and it compiles. Qualifying the call (`TSvc.TInst.Mk` rather than the inherited-name `TInst.Mk`) does NOT help, and the caller need not descend from the nested type's owner. This is the `uses Generics.Defaults` wall on the rtl-generics rung: generics.defaults.pas declares `TComparerService.TInstance` with two static class functions and calls them 62 times from `class constructor THashService<T>.Create`. BOTH are broken there, not just the reported one -- `Error` aborts at the FIRST failing fixup, so commenting out the 25 CreateSelector call sites moves the message to `TInstance.Create`. Do not read the reported name as the only one."
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

## 2026-09-09 (frankS) — FIXED, and `uses Generics.Defaults` now COMPILES AND RUNS

**Neither `nested` nor the inherited spelling was load-bearing; `record` and
`specialized caller` were, and the mechanism is a decl/impl pair that disagrees
about Self.**

`PXXDBG=p.proc` (added with the fix — one guarded line per RegisterProc) on the
30-line repro:

```
PXXDBG p.proc reg idx=141 name=TInst.Mk nparams=2 ptypes=5 17    <- the DECLARATION
PXXDBG p.proc reg idx=143 name=TInst.Mk nparams=2 ptypes=17 17   <- the IMPLEMENTATION
```

`5` is tyRecord, `17` is tyPointer. `pasparser_decl.inc`'s record-method Self
block has three arms — class helper, helper target, else **the record BY
REFERENCE** — and no static arm at all. `pasparser_proc.inc`'s impl side types
every static method's Self as **the bare class reference**. `FindProcOverloadRec`
compares the signature, could not match the two, and the implementation minted a
second proc row instead of filling the declaration's.

The same record method as an INSTANCE method registers one row and always
worked: both sides say tyRecord there.

**Fixed on the DECL side** — a record `class` method (static by construction:
`UMthIsStatic` is set from the same `RecordMethodClassPrefix` flag) now registers
the bare class-reference Self, including `ProcParamPtrElemTk = tyClass`, which is
part of the signature the impl side supplies.

**The impl side is the wrong side and it is the side anyone would try first.**
Making the implementation adopt the record-by-reference shape also merges the
rows — and every such call then SEGFAULTS, because a static call site has no
instance to pass. Measured before the decl-side fix, not reasoned.

**Result.** `uses Generics.Defaults` compiles and runs (`defaults ok`, rc 0) at
binary `4b5ee0c8e11e`. Regression test
`test_a_records_static_class_function_binds_from_a_specialized_body`, byte-matching
fpc 3.2.2 `-Mdelphi`, covering the top-level record, the class-nested record and
a plain non-specialized caller. Without the fix it does not compile at all.
`uses Generics.Collections` is unchanged at `unknown type: PT`
(collections.pas:120/123), which is frankZ's.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 163e146eb.
