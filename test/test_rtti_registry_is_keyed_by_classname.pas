{ THE REGISTRY MUST BE KEYED BY THE STRING ClassName RETURNS.

  The class blob's name word holds ClassRttiName(ci) -- canonical for a
  specialization alias -- and the registry used to intern the RAW TokSlice
  spelling instead. For every ordinary class those two strings are identical,
  which is why this went unseen: the divergence needs a SPECIALIZATION, where
  the alias spelling (`TIntBox`) and the canonical name (`TBox<System.LongInt>`)
  are different strings.

  Measured before the fix: ClassName gave `TBox<System.LongInt>`,
  GetClass('TIntBox') FOUND, and GetClass(b.ClassName) MISSING -- i.e. the one
  round trip the registry exists for was the one that failed, while a lookup
  under a name no instance ever reports succeeded.

  THE PLAIN CLASS IS THE CONTROL and it is why the alias rows mean something:
  a registry that found nothing at all would satisfy the MISSING row, and a
  registry that found everything would satisfy the FOUND row. Only the three
  together pin the keying. TZebra is also declared AFTER the alias deliberately:
  InternStr appends to Data[] and the registry is read at a fixed 16-byte
  stride, so a name interned mid-table would push every later entry off-stride.
  That did not reproduce, and a later class is what would show it if it ever did.

  feature-a-unreferenced-class-rtti-keeps-every-method-alive }
program test_rtti_registry_is_keyed_by_classname;
uses typinfo;
type
  generic TBox<T> = class
    V: T;
    procedure Touch; virtual;
  end;
  TIntBox = specialize TBox<Integer>;
  TZebraDeclaredAfterTheAlias = class
    procedure Z; virtual;
  end;
procedure TBox.Touch; begin end;
procedure TZebraDeclaredAfterTheAlias.Z; begin end;

procedure Show(const label_: AnsiString; found: Boolean);
begin
  if found then WriteLn(label_, ' FOUND') else WriteLn(label_, ' MISSING');
end;

var b: TIntBox;
begin
  b := TIntBox.Create;
  WriteLn('ClassName=', b.ClassName);
  Show('by-ClassName', GetClass(b.ClassName) <> nil);
  Show('by-alias-spelling', GetClass('TIntBox') <> nil);
  Show('plain-class-control', GetClass('TZebraDeclaredAfterTheAlias') <> nil);
end.
