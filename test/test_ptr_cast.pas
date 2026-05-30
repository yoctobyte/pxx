program test_ptr_cast;
{ C4: PType(addr) typed pointer casts — preserving element type for ^/. access.
  Phase 2 (typed-pointer) step C4. }
type
  TPoint = record
    X: Integer;
    Y: Integer;
  end;
  PPoint = ^TPoint;

  TNode = record
    Value: Int64;
    Tag:   Integer;
  end;
  PNode = ^TNode;
  PInt64 = ^Int64;

var
  raw:   Int64;
  pt:    TPoint;
  nd:    TNode;
  vptr:  PInt64;
  ptptr: PPoint;
  ndptr: PNode;

begin
  { --- PInt64 cast: read via PInt64(vptr)^ --- }
  raw  := 12345;
  vptr := @raw;
  writeln(PInt64(vptr)^);        { expect 12345 }

  { --- Write via cast: PInt64(vptr)^ := val --- }
  PInt64(vptr)^ := 99999;
  writeln(raw);                  { expect 99999 }

  { --- PPoint cast: read fields via PPoint(ptptr)^.field --- }
  pt.X := 77;
  pt.Y := 88;
  ptptr := @pt;
  writeln(PPoint(ptptr)^.X);    { expect 77 }
  writeln(PPoint(ptptr)^.Y);    { expect 88 }

  { --- Write field via cast: PPoint(ptptr)^.X := val --- }
  PPoint(ptptr)^.X := 42;
  writeln(pt.X);                { expect 42 }

  { --- PNode cast --- }
  nd.Value := 1111;
  nd.Tag   := 7;
  ndptr := @nd;
  writeln(PNode(ndptr)^.Value); { expect 1111 }
  writeln(PNode(ndptr)^.Tag);   { expect 7 }
  PNode(ndptr)^.Tag := 99;
  writeln(nd.Tag);              { expect 99 }

  { --- Chains: read two fields in sequence --- }
  pt.X := 100; pt.Y := 200;
  ptptr := @pt;
  writeln(PPoint(ptptr)^.X);   { expect 100 }
  writeln(PPoint(ptptr)^.Y);   { expect 200 }

  { --- Built-in casts: Pointer(raw_addr), Int64(ptr) --- }
  raw := Int64(ptptr);
  if raw = Int64(ptptr) then
    writeln('builtin_cast: int64 ok')
  else
    writeln('builtin_cast: int64 fail');

  ptptr := Pointer(raw);
  writeln(PPoint(ptptr)^.X);   { expect 100 }
end.
