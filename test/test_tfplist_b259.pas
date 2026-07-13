program test_tfplist_b259;
{ TFPList — FPC's plain pointer list. In FPC it is the non-notifying list and TList adds
  the Notify hook on top; our TList already carries exactly TFPList's surface, so TFPList
  is that list under the name FPC sources actually write. fcl-fpcunit's suites are full of
  it. A descendant rather than an alias, so it stays a distinct class for is/as and for a
  parameter typed TFPList. }
uses classes;
type
  PInt = ^Integer;    { PInteger(p)^ as a CAST does not parse yet —
                        bug-pascal-builtin-pointer-type-cast }
var
  l: TFPList;
  a, b, c: Integer;
begin
  l := TFPList.Create;
  a := 10; b := 20; c := 30;

  l.Add(@a);
  l.Add(@b);
  l.Add(@c);
  writeln('count=', l.Count);
  writeln('idx-b=', l.IndexOf(@b));
  writeln('item0=', PInt(l[0])^);

  l.Delete(0);
  writeln('after-delete=', l.Count, ' item0=', PInt(l[0])^);

  l.Remove(@c);
  writeln('after-remove=', l.Count, ' item0=', PInt(l[0])^);

  writeln('is-tlist=', l is TList);

  l.Clear;
  writeln('after-clear=', l.Count);
  l.Free;
end.
