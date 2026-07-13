{ TObject.ClassType / TObject.InheritsFrom / TClass.InheritsFrom -- FPC has them on
  TObject in System, so they are reached with no `uses`. Each is a walk over the RTTI
  blob, and each takes both shapes the receiver can have:

    an INSTANCE       blob is __pxxRttiOf(x)   ([[x+0] - 8])
    a CLASS REFERENCE blob IS the value        (a TClass value is the blob pointer)

  ClassType therefore needs no call at all: it is that blob pointer, retyped.

  The chain `E.ClassType.InheritsFrom(C)` is fpcunit's AssertException, and it is the
  reason the ops must compose: ClassType yields a class reference, and the NEXT
  selector applies to that, not to E.

  InheritsFrom is REFLEXIVE, as in FPC: a class inherits from itself. }
program test_classtype_inheritsfrom_b274;
type
  TBase = class end;
  TMid = class(TBase) end;
  TLeaf = class(TMid) end;
  TOther = class end;
function GetN(C: TClass): string;
begin
  if C = nil then Result := '<NIL>' else Result := C.ClassName;
end;
var
  l: TLeaf;
  cr: TClass;
begin
  l := TLeaf.Create;
  { ClassType on an instance -> TClass }
  writeln('classtype name: ', GetN(l.ClassType));
  { the fpcunit chain }
  writeln('chain leaf<-mid: ', l.ClassType.InheritsFrom(TMid));
  writeln('chain leaf<-base: ', l.ClassType.InheritsFrom(TBase));
  writeln('chain leaf<-other: ', l.ClassType.InheritsFrom(TOther));
  { reflexive, as in FPC }
  writeln('chain leaf<-leaf: ', l.ClassType.InheritsFrom(TLeaf));
  { InheritsFrom directly on an instance }
  writeln('inst leaf<-base: ', l.InheritsFrom(TBase));
  { on a class-reference variable }
  cr := l.ClassType;
  writeln('var name: ', GetN(cr));
  writeln('var leaf<-mid: ', cr.InheritsFrom(TMid));
  writeln('var leaf<-other: ', cr.InheritsFrom(TOther));
  { on a class-reference literal }
  writeln('lit mid<-base: ', TMid.InheritsFrom(TBase));
  writeln('lit base<-leaf: ', TBase.InheritsFrom(TLeaf));
  { chained ClassName off ClassType }
  writeln('chain name: ', l.ClassType.ClassName);
end.
