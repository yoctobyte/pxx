{ An initialised array of CLASS REFERENCES -- the elements are class NAMES:

    DefaultJSONInstanceTypes : Array[TJSONInstanceType] of TJSONDataClass =
      (TJSONData, TJSONIntegerNumber, ... );        { fpjson: a Var }
    MinJSONInstanceTypes : Array[...] of TJSONDataClass = ( ... );   { ...and a Const }

  A class reference's value is its RTTI blob address, which is only known after EmitRTTI --
  so it cannot be a ConstEval ordinal. The element records the class INDEX and the
  initializer emits an AN_CLASSREF, the same node a class name used as a value anywhere
  else produces; the address is patched in at link time through the per-class data-ref
  sentinel.

  Both the CONST and the VAR array paths needed it (fpjson uses one of each), and the
  class-reference OPERATIONS had to learn to answer on an array ELEMENT, not just a bare
  identifier -- fpjson reads `MinJSONInstanceTypes[AType].ClassName`.

  Not covered, and filed: calling a class METHOD through such an element
  (bug-pascal-member-access-on-pointer-silently-accepted). }
program test_classref_array_const_b285;
type
  TKind = (kBase, kMid, kLeaf);
  TBase = class
    class function Tag: string;
  end;
  TBaseClass = class of TBase;
  TMid = class(TBase) end;
  TLeaf = class(TMid) end;
class function TBase.Tag: string;
begin Result := Self.ClassName; end;
const
  ClassTable: array[TKind] of TBaseClass = (TBase, TMid, TLeaf);
var
  Table2: array[TKind] of TBaseClass = (TLeaf, TBase, TMid);
  k: TKind;
begin
  for k := kBase to kLeaf do write(ClassTable[k].ClassName, ' ');
  writeln;
  for k := kBase to kLeaf do write(Table2[k].ClassName, ' ');
  writeln;
  { they really are class references: InheritsFrom answers on them }
  writeln('leaf<-base: ', ClassTable[kLeaf].InheritsFrom(TBase));
  writeln('base<-leaf: ', ClassTable[kBase].InheritsFrom(TLeaf));
end.
