program test_ptr_deref_field;
{ C3: p^.field — dereferencing a typed pointer then accessing a record field.
  Phase 2 (typed-pointer) step C3. }
type
  TPoint = record
    X: Integer;
    Y: Integer;
  end;
  PPoint = ^TPoint;

  TNode = record
    Value: Int64;
    Tag: Integer;
  end;
  PNode = ^TNode;

var
  pt: TPoint;
  p:  PPoint;
  nd: TNode;
  q:  PNode;
  arr: array[0..1] of TPoint;
  pa: PPoint;

begin
  { Basic read/write via p^.field }
  pt.X := 10;
  pt.Y := 20;
  p := @pt;
  writeln(p^.X);     { expect 10 }
  writeln(p^.Y);     { expect 20 }

  p^.X := 42;
  p^.Y := 99;
  writeln(pt.X);     { expect 42 }
  writeln(pt.Y);     { expect 99 }

  { Two-field record }
  nd.Value := 1234;
  nd.Tag   := 5;
  q := @nd;
  writeln(q^.Value); { expect 1234 }
  writeln(q^.Tag);   { expect 5 }
  q^.Value := 9999;
  writeln(nd.Value); { expect 9999 }

  { Pointer indexing then deref field: pa[i]^.X — if supported,
    or at least p^.X with p set to &arr[1] }
  arr[0].X := 100; arr[0].Y := 200;
  arr[1].X := 300; arr[1].Y := 400;
  pa := @arr[0];
  writeln(pa^.X);    { expect 100 }
  pa := @arr[1];
  writeln(pa^.X);    { expect 300 }
  pa^.Y := 777;
  writeln(arr[1].Y); { expect 777 }
end.
