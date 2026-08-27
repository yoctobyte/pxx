---
slug: bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer
track: P
prio: 65
type: bug
status: backlog
blocked-by: []
summary: "Passing a class instance where a typed pointer (^TSomeRecord) is expected compiles silently and reinterprets the object as that record; FPC rejects it (`Incompatible type for arg no. 1: Got \"TSub\", expected \"PBlob\"`). Two consequences: a silent memory-safety hole with no cast written, and an overload resolution that picks a pointer arm over an exact class arm — which is what stops typinfo's GetPropInfo(AnObject, 'Name') facade overload from ever being selected."
---

# A class instance converts implicitly to any typed pointer

- **Track P** (Pascal frontend — assignment/argument compatibility).
- Found 2026-08-28 by frankB (Track B) while adding the instance-taking
  overloads for [[feature-typinfo-facade-unit]]. Measured against pin **v389**
  (`325b4479070a`).

## Repro — 14 lines, no overloads involved

```pascal
program imp;
type
  TBlob = record A: Int64; end;
  PBlob = ^TBlob;
  TSub = class(TObject) end;
function OnlyPointer(p: PBlob): Int64;
begin
  if p = nil then OnlyPointer := -1 else OnlyPointer := p^.A;
end;
var s: TSub;
begin
  s := TSub.Create;
  WriteLn(OnlyPointer(s));    { pxx: compiles, reads the object as a TBlob }
end.
```

```
$ pxx imp.pas imp
ok: imp

$ fpc -O- -Mobjfpc imp.pas
imp.pas(14,55) Error: Incompatible type for arg no. 1: Got "TSub", expected "PBlob"
```

No cast is written anywhere. The object's header is read as the record's
fields.

## Why this is a bug and not our usual laxness

The dialect is deliberately laxer than FPC in places, and CLAUDE.md's compat
table says "we accept a form FPC rejects → not a defect". **This one is the
silent-wrong-behaviour escape, not that row.** The accepted form does not do
something harmless and useful; it reinterprets one type's memory as an
unrelated one, with no diagnostic and no syntax at the call site to warn a
reader. A `Pointer` parameter accepting an object is the useful laxness and is
NOT what this is about — that stays. This is about a pointer to a *specific*
record type silently accepting an object of an unrelated class.

## Second consequence: overload resolution

Because the conversion is legal, a pointer-taking overload is a *viable
candidate* for a class argument, and it is then preferred over the exact class
match:

```pascal
function GetPropInfo(cls: PClassRTTI; const name: string): PPropInfo; overload;
function GetPropInfo(instance: TObject; const name: string): PPropInfo; overload;
...
GetPropInfo(SomeObject, 'Num')   { binds to the PClassRTTI arm -> SIGSEGV }
```

Measured, not inferred: instrumenting the `TObject` arm with a `WriteLn` on
entry shows it is **never entered**. Giving the same body a unique name makes it
work, and moving the two declarations adjacent changes nothing.

This is what blocks `lib/rtl/typinfo.pas`'s instance-taking facade overloads
(`GetPropInfo(AnObject, 'Caption')` — the spelling every FPC consumer uses).
Those overloads are LEFT IN PLACE as platonic code per the standing rule, marked
`blocked-by:` this ticket; the declaration comment there states the hazard so
nobody reads their presence as a promise.

## Note on reduction — this one did NOT reduce

Worth recording because it cost the most time. Synthetic two-overload repros
**pass**: a unit with `Pick(PBlob)` / `Pick(TObject)`, called with either a bare
`TObject` or a descendant, with the declarations adjacent or separated by
unrelated ones, with the inner call self-recursive — every one of them selects
the object arm correctly. The defect only showed in `typinfo.pas` itself, which
is why the repro above drops overloading entirely and demonstrates the
underlying conversion instead. Same lesson as
[[bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module]]: when
a passing probe is not evidence, stop varying the input and go after the
mechanism.

## Gate

The 14-line program is a compile ERROR, matching FPC's diagnostic in substance;
`GetPropInfo(AnObject, 'Num')` then selects typinfo's `TObject` overload and
`test/lib_typinfo_props.pas` can assert the instance spelling directly (it
currently routes through `GetInstanceRTTI` and says why). `make test` +
self-host fixedpoint.
