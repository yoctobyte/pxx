program test_new_dispose;
{ New(p) allocates SizeOf(p^) into p; Dispose(p) frees it. A freed block is
  reused by the next New of a fitting size. }
type
  PInt = ^Integer;
  TRec = record x, y: Integer; end;
  PRec = ^TRec;
var
  pi: PInt;
  pr, pr2: PRec;
begin
  New(pi);
  pi^ := 1234;
  writeln(pi^);                                  { 1234 }

  New(pr);
  pr^.x := 7; pr^.y := 9;
  writeln(pr^.x + pr^.y);                         { 16 }

  Dispose(pr);
  New(pr2);
  if pr2 = pr then writeln(1) else writeln(0);    { 1: reused }

  Dispose(pi);
end.
