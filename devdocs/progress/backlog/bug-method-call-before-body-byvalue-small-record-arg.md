# Method call before body: by-value <=8-byte record arg mislowers (i386 error; x64 program-level unresolved-forward)

- **Type:** bug (shared internals — call lowering / decl order)
- **Track:** A
- **Status:** backlog
- **Opened:** 2026-07-03
- **Found while:** feature-i386-threadsafe-locks — palthreadobj's
  ThreadObjLauncher calls TThread.Synchronize(const m: TThreadMethod)
  (an 8-byte record) BEFORE Synchronize's body is compiled.

## Repro

```pascal
program reclaunch3;
type
  TM = record Code: Pointer; Data: Pointer; end;   { 8 bytes on i386 }
  TC = class
    FM: TM;
    procedure S(const m: TM);
  end;
procedure Launch(arg: Pointer);
var t: TC; mt: TM;
begin
  t := TC(arg);
  mt.Code := t.FM.Code;
  mt.Data := t.FM.Data;
  if mt.Code <> nil then
    t.S(mt);                 { call BEFORE TC.S's body is parsed }
end;
procedure TC.S(const m: TM);
begin
  writeln(Int64(m.Code));
end;
var c: TC;
begin
  c := TC.Create; c.FM.Code := Pointer(5); Launch(Pointer(c));
end.
```

- `--target=i386`: `error: target i386: only ordinal/pointer/string
  variables supported yet` (reported at the CALLER's end line).
- x86-64 (program-level): `error: unresolved forward: TC.S`.
- Moving `TC.S`'s body ABOVE `Launch` compiles and runs correctly on both.
- In a UNIT (interface decl + implementation body), x86-64 compiles fine but
  i386 still errors — this is exactly what bit palthreadobj.

## Analysis pointers

- Records <= 8 bytes are NOT promoted to by-ref (parser.inc ~13985: only
  `RecSize > 8` or 32-bit CORBA fat pointers promote), so the arg goes down
  the by-value small-record path.
- The pre-body call site appears to lower that path against param metadata
  that is only complete once the body's param syms exist — same landmine
  family as the v153 `ProcParam*` persistence fixes (calls made before the
  body must lower identically to ones after).
- Suspect: the by-value-record arg branch reads something via
  `Params[i].SymIdx` / un-persisted state instead of
  `ProcParamRecId`/`ProcParamIsConst`.

## Workaround (landed 2026-07-03)

lib/rtl/palthreadobj.pas forward-declares ThreadObjLauncher and defines its
body AFTER TThread.Synchronize, so the call lowers with the callee's body
already compiled. Revert the reorder when this is fixed (it is commented at
the site).

## Acceptance

The repro compiles and prints 5 on x86-64 and i386 (qemu) with the callee
body in either position; make test + self-host byte-identical.
