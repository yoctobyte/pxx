program test_rv32_pointer_compare_is_one_word;
{ On riscv32 a pointer or class reference compared with nil or another
  pointer is a one-word compare, not the 64-bit pair compare. The ordered
  compares are unsigned: addresses at and above 2^31 must sort above the
  low ones. Prints the same on x64. }
{$mode objfpc}
type
  TThing = class
    n: Integer;
  end;

var
  lo, hi, top, p: Pointer;
  a, b, c: TThing;
  i: Integer;

function B2S(x: Boolean): string;
begin
  if x then Result := 'T' else Result := 'F';
end;

procedure Ordered(const name: string; x, y: Pointer);
begin
  writeln(name, ' = ', B2S(x = y), ' <> ', B2S(x <> y), ' < ', B2S(x < y),
    ' <= ', B2S(x <= y), ' > ', B2S(x > y), ' >= ', B2S(x >= y));
end;

function IsNil(q: Pointer): Boolean;
begin
  Result := q = nil;
end;

begin
  lo := Pointer(PtrUInt($10));
  hi := Pointer(PtrUInt($80000000));
  top := Pointer(PtrUInt($FFFFFFF0));
  p := nil;
  writeln('nil: ', B2S(IsNil(p)), ' ', B2S(IsNil(lo)), ' ', B2S(IsNil(hi)), ' ', B2S(IsNil(top)));
  if p = nil then writeln('p = nil') else writeln('p <> nil');
  if lo <> nil then writeln('lo <> nil') else writeln('lo = nil');
  if nil = hi then writeln('nil = hi') else writeln('nil <> hi');
  Ordered('lo,hi', lo, hi);
  Ordered('hi,lo', hi, lo);
  Ordered('hi,top', hi, top);
  Ordered('top,top', top, top);
  Ordered('nil,top', nil, top);
  Ordered('top,nil', top, nil);

  a := TThing.Create; b := TThing.Create; c := nil;
  writeln('class: ', B2S(a = nil), ' ', B2S(c = nil), ' ', B2S(a = b), ' ', B2S(a <> b),
    ' ', B2S(a = a), ' ', B2S(nil <> c));
  c := a;
  if c = a then writeln('c = a') else writeln('c <> a');
  c := nil;
  for i := 1 to 3 do
  begin
    if c = nil then begin c := b; writeln('round ', i, ': was nil'); end
    else begin c := nil; writeln('round ', i, ': was set'); end;
  end;
  a.Free; b.Free;
end.
