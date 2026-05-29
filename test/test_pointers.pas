program test_pointers;
type
  TPoint = record
    x: Integer;
    y: Integer;
  end;

var
  a, b: Integer;
  p: ^Integer;
  p2: ^Integer;
  pt: TPoint;
  pPt: ^TPoint;

procedure UpdateVal(ptr: ^Integer; val: Integer);
begin
  ptr^ := val;
end;

begin
  a := 10;
  b := 20;

  { 1. Basic Address-of and Dereference }
  p := @a;
  writeln('a = ', a); { 10 }
  writeln('p^ = ', p^); { 10 }

  p^ := 42;
  writeln('a modified via p^ = ', a); { 42 }

  { 2. Pointer assignment and comparison }
  p2 := p;
  writeln('p2^ = ', p2^); { 42 }

  if p = p2 then
    writeln('p = p2: OK')
  else
    writeln('p = p2: FAIL');

  { 3. nil checks }
  p2 := nil;
  if p2 = nil then
    writeln('p2 = nil: OK')
  else
    writeln('p2 = nil: FAIL');

  if p <> nil then
    writeln('p <> nil: OK')
  else
    writeln('p <> nil: FAIL');

  { 4. Pointer parameter passing }
  UpdateVal(@b, 100);
  writeln('b modified via parameter = ', b); { 100 }

  { 5. Pointer to record }
  pt.x := 5;
  pt.y := 12;
  pPt := @pt;
  writeln('pPt^.x = ', pPt^.x); { 5 }
  writeln('pPt^.y = ', pPt^.y); { 12 }

  pPt^.x := 99;
  pPt^.y := 88;
  writeln('pt.x = ', pt.x); { 99 }
  writeln('pt.y = ', pt.y); { 88 }

  writeln('all pointer tests done!');
end.
