---
slug: bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer
track: P
prio: 65
type: bug
status: working
blocked-by: []
summary: "Passing a class instance where a typed pointer (^TSomeRecord) is expected compiles silently and reinterprets the object as that record; FPC rejects it (`Incompatible type for arg no. 1: Got \"TSub\", expected \"PBlob\"`). Two consequences: a silent memory-safety hole with no cast written, and an overload resolution that picks a pointer arm over an exact class arm — which is what stops typinfo's GetPropInfo(AnObject, 'Name') facade overload from ever being selected."
owner: frankA
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

---

## Root cause (frankA, 2026-08-28)

`symtab.inc:6963`, inside `TypesCompatible`:

```pascal
{ A class instance converts implicitly to a rooted object reference — the
  builtin TObject / `object` param type is a tyPointer (elem tyClass), so a
  `P(o: TObject)` plain routine must accept any tyClass argument... }
if (pType = tyPointer) and (aType = tyClass) then
begin
  Result := True;
  Exit;
end;
```

The rule is **load-bearing and right in intent** — the builtin `TObject`
parameter type really is a `tyPointer` whose ELEMENT is `tyClass`, so removing it
breaks every `P(o: TObject)`. What is wrong is that it is *blanket*: it also
accepts a pointer whose element is a **record**, which is this ticket.

The discriminator is the pointer's **element type**, and `TypesCompatible`
receives only KINDS — never identities. That is the same architectural gap
`MatchArgNilOk` was added to close, and its comment says so almost verbatim:
"pxx types nil as a tyPointer literal, so the kind channel let it through". So
this defect has an exact in-repo precedent, and the house style for it is
established.

### Where the fix goes

**`MatchArgRecMismatch(i, j, aTk)`** (`symtab.inc:7385`) — already the home for
this exact family: "this argument definitely cannot bind this parameter"
rejections, each carrying its own ticket reference. Two are there now (a scalar
argument binding an array parameter; an array argument binding a scalar one).
This is the third of the same shape.

No new side channel is needed: `aTk` is already `tyClass` for a class-instance
argument, and the parameter's element type is reachable as
`Syms[Procs[i].Params[j].SymIdx].PtrElemTk` (`TParam` itself does not carry it,
`TSym` does). Reject when the argument is `tyClass`, the parameter is
`tyPointer`, the parameter is not untyped, and its `PtrElemTk` is not a class.

`TypesCompatible` stays exactly as it is — the coarse kind channel, with its
other callers untouched. `MatchArgRecMismatch` is already ANDed in beside
`MatchParamCompatible` at every match site, and a single-candidate call walks the
same path (a candidate chain of length one), so **one site covers the
no-overload repro and the overload consequence together**.

### Guard test landed ahead of the fix

`test/test_class_arg_to_pointer_param_boundary` pins the **legitimate** half so
tightening the other half cannot take it with it: a class instance binding an
untyped `Pointer`, binding a `TObject` formal, both with a descendant, `nil`
through both, and a genuine pointer-to-class argument. It passes today and must
keep passing; FPC accepts all of it and agrees byte for byte. The illegitimate
half is a compile-time diagnostic and cannot be asserted from inside a Pascal
program, so it is gated separately — same split as `test/cerror_directive.c`.

Over-reach is the real risk in this fix (the rule exists for a reason), which is
why the guard is in the tree before the change.

### Blocked on lane ownership, not on analysis

The fix is `symtab.inc` — shared core, Track A's file-lane, and inside the
boundary this session was given while Track O runs in `~/frank-optimize`. Per
CLAUDE.md a shared-internals change is a Track A change regardless of the Track P
symptom. Raised with the coordinator rather than edited; analysis above is
complete and the change is ~15 lines in one function.
