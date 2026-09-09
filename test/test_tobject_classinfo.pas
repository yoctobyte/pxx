{ TObject.ClassInfo — the last member of feature-pascal-builtin-tobject-class
  that was still PXX-REJECT, and the one that was a JUDGMENT CALL rather than
  an implementation choice (decide-tobject-classinfo-blob-or-refusal, decided
  2026-08-25: answer with the typinfo facade's PTypeInfo, not our raw blob).

  ClassInfo now returns exactly what TypeInfo(TThatClass) returns — the 24-byte
  {Kind; NamePtr; DataPtr} header whose DataPtr points at the class blob — so
  BOTH kinds of caller are served, and the file asserts both:

    identity      `x.ClassInfo = TypeInfo(T)`, the shape a registry uses
    layout walk   `PTypeInfo(x.ClassInfo)^.Kind = tkClass`, the shape typinfo
                  and every RTTI-walking library uses

  TWO ROWS HERE MUST BE FALSE AND THEY ARE THE ONLY REASON THE FILE IS A GUARD.

  - `o.ClassInfo = TypeInfo(TBase)` where `o: TBase` HOLDS a TDer. ClassInfo is
    a runtime member on a possibly-dynamic receiver; anything that answered
    from the DECLARED type would print TRUE here and TRUE on the row above it,
    and every other row in the file would still pass. This is why the header is
    minted per declared class and reached through the blob, rather than folded
    into the compile-time TypeInfo() path.
  - `TBase.ClassInfo = TDer.ClassInfo`. A ClassInfo that answered nil, or one
    shared header for everything, satisfies every TRUE row by accident.

  Returning the raw blob — the cheaper option, and the one the decision
  refused — is caught by the Kind rows: a walker would read the blob's +0
  word, an interned-name POINTER, and take its low byte as a TTypeKind. Non-nil
  and plausible, with no diagnostic. That is frontend-compat-philosophy.md's
  "a silent wrong VALUE is a bug in any dialect".

  Expected output is fpc 3.2.2's own (-Mobjfpc -O1); every spelling here is one
  both compilers accept, which is why the kind rows compare against `tkClass`
  rather than printing Ord(Kind) (FPC's Kind is an enum field, ours an Int64).
  feature-a-classinfo-returns-the-typinfo-header }
{$mode objfpc}{$H+}
program test_tobject_classinfo;
uses typinfo, tobject_unitname_unit;
type
  TBase = class(TObject)
    X: Integer;
  end;
  TDer = class(TBase)
    Y: Integer;
  end;
var
  o: TBase;
  c: TClass;
  u: TInUnit;
begin
  { identity, on a class reference }
  WriteLn(TObject.ClassInfo = TypeInfo(TObject));
  WriteLn(TBase.ClassInfo   = TypeInfo(TBase));
  WriteLn(TDer.ClassInfo    = TypeInfo(TDer));

  { identity, on an INSTANCE reached through a variable of the PARENT's type —
    the row that separates a runtime answer from a declared-type one }
  o := TDer.Create;
  WriteLn(o.ClassInfo = TypeInfo(TDer));
  WriteLn(o.ClassInfo = TypeInfo(TBase));

  { two classes never share a header }
  WriteLn(TBase.ClassInfo = TDer.ClassInfo);
  WriteLn(o.ClassInfo <> nil);

  { through a TClass VALUE, which is the shape a factory holds }
  c := TDer;
  WriteLn(c.ClassInfo = TypeInfo(TDer));

  { a class declared in another UNIT: its header must be the same one
    TypeInfo() mints there, not a second copy }
  u := TDerived.Create;
  WriteLn(u.ClassInfo = TypeInfo(TDerived));
  WriteLn(TInUnit.ClassInfo = TypeInfo(TInUnit));

  { the layout walker's half }
  WriteLn(PTypeInfo(o.ClassInfo)^.Kind = tkClass);
  WriteLn(PTypeInfo(TObject.ClassInfo)^.Kind = tkClass);
  WriteLn(GetTypeData(PTypeInfo(o.ClassInfo)) <> nil);
end.
