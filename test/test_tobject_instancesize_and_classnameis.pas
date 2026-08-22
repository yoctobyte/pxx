{ TObject.InstanceSize and TObject.ClassNameIs — two of FPC's System-level root
  class operations, reachable with no `uses`. InstanceSize was pure omission:
  rtti_emit has always written the instance size into the class blob at +16, and
  only the accessor was missing. ClassNameIs is a case-insensitive compare of
  the class's OWN name — it does not walk the parent chain.
  feature-a-tobject-instancesize-and-classnameis }
program test_tobject_instancesize_and_classnameis;

type
  TBase = class
    FA: Integer;
    FB: Integer;
  end;
  TDer = class(TBase)
    FC: Int64;
  end;

var
  b: TBase;
  d: TDer;
  o: TObject;
  c: TClass;
begin
  b := TBase.Create;
  d := TDer.Create;
  o := d;                       { a STATIC TObject holding a TDer }

  { class-reference side and instance side must agree }
  WriteLn('cls  ', TBase.InstanceSize, ' ', TDer.InstanceSize);
  WriteLn('inst ', b.InstanceSize, ' ', d.InstanceSize);

  { the polymorphic case: a static TObject receiver must report the RUNTIME
    class's size, not TObject's — this is what proves the blob is reached
    through the instance rather than resolved at compile time }
  WriteLn('poly ', o.InstanceSize);

  { ...and through a TClass variable, the other runtime path }
  c := TDer;
  WriteLn('ref  ', c.InstanceSize);

  WriteLn('grow ', TDer.InstanceSize > TBase.InstanceSize);

  { ClassNameIs: case-insensitive, exact class only, both receiver shapes }
  WriteLn('nis1 ', b.ClassNameIs('TBase'), ' ', b.ClassNameIs('tbase'), ' ',
          b.ClassNameIs('TDer'));
  WriteLn('nis2 ', TDer.ClassNameIs('TDER'), ' ', TDer.ClassNameIs('TBase'));

  { a derived instance is NOT its parent's name — ClassNameIs does not inherit,
    unlike InheritsFrom right below it }
  WriteLn('nis3 ', o.ClassNameIs('TDer'), ' ', o.ClassNameIs('TBase'), ' ',
          d.InheritsFrom(TBase));

  { FPC allows the empty-parens spelling on the no-argument form }
  WriteLn('paren ', b.InstanceSize(), ' ', b.ClassName());

  b.Free;
  d.Free;
end.
