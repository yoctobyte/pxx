program test_dynarray_insert_delete;
{ Dynamic-array Insert/Delete intrinsics (feature-dynarray-insert-delete).
  Each case self-checks and prints `ok <n>` or `FAIL <n>`; the final line is
  the oracle. Semantics verified against real FPC 3.2.2 (clamping included).
  First cut: plain depth-1 dyn-array variables, non-managed element types
  (managed/nested/record elements are a clean compile error). }

var
  okCount: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

{ ---- Delete: middle / front / clamping ---- }
procedure DeleteBasics;
var a: array of Integer; i: Integer;
begin
  SetLength(a, 5);
  for i := 0 to 4 do a[i] := (i + 1) * 10;
  Delete(a, 1, 2);                      { 10 40 50 }
  Chk(1, (Length(a) = 3) and (a[0] = 10) and (a[1] = 40) and (a[2] = 50));
  Delete(a, 0, 1);                      { 40 50 }
  Chk(2, (Length(a) = 2) and (a[0] = 40) and (a[1] = 50));
  Delete(a, 5, 3);                      { index past end: no-op }
  Chk(3, (Length(a) = 2) and (a[0] = 40));
  Delete(a, 1, 99);                     { count clamped to tail }
  Chk(4, (Length(a) = 1) and (a[0] = 40));
  Delete(a, -1, 5);                     { negative index: no-op }
  Chk(5, (Length(a) = 1) and (a[0] = 40));
  Delete(a, 0, 1);                      { empty }
  Chk(6, Length(a) = 0);
  Delete(a, 0, 1);                      { delete on empty: no-op }
  Chk(7, Length(a) = 0);
end;

{ ---- Insert: positions / clamping / empty ---- }
procedure InsertBasics;
var a: array of Integer;
begin
  Insert(42, a, 0);                     { insert into empty/nil }
  Chk(8, (Length(a) = 1) and (a[0] = 42));
  Insert(7, a, 0);                      { front }
  Chk(9, (Length(a) = 2) and (a[0] = 7) and (a[1] = 42));
  Insert(9, a, 2);                      { end }
  Chk(10, (Length(a) = 3) and (a[2] = 9));
  Insert(8, a, 1);                      { middle }
  Chk(11, (Length(a) = 4) and (a[0] = 7) and (a[1] = 8) and (a[2] = 42) and (a[3] = 9));
  Insert(5, a, 99);                     { index clamped to end }
  Chk(12, (Length(a) = 5) and (a[4] = 5));
  Insert(1, a, -3);                     { index clamped to 0 }
  Chk(13, (Length(a) = 6) and (a[0] = 1) and (a[1] = 7));
end;

{ ---- Double elements (8-byte, FP store into the gap) ---- }
procedure Doubles;
var d: array of Double;
begin
  SetLength(d, 2); d[0] := 1.5; d[1] := 2.5;
  Insert(9.25, d, 1);
  Chk(14, (Length(d) = 3) and (d[0] = 1.5) and (d[1] = 9.25) and (d[2] = 2.5));
  Delete(d, 0, 1);
  Chk(15, (Length(d) = 2) and (d[0] = 9.25) and (d[1] = 2.5));
end;

{ ---- non-managed record elements: Delete works (raw byte copy) ---- }
type TPt = record x, y: Integer; end;
procedure RecDelete;
var r: array of TPt; i: Integer;
begin
  SetLength(r, 3);
  for i := 0 to 2 do begin r[i].x := i; r[i].y := i * 100; end;
  Delete(r, 1, 1);
  Chk(16, (Length(r) = 2) and (r[0].x = 0) and (r[1].x = 2) and (r[1].y = 200));
end;

{ ---- loop churn in a proc: fresh-temp refcounts must balance (no leak /
       double free); also exercises the branch-not-taken prologue nil-init ---- }
procedure Churn(doIt: Boolean);
var a: array of Integer; i: Integer;
begin
  if doIt then
  begin
    SetLength(a, 100);
    for i := 0 to 99 do a[i] := i;
    for i := 1 to 1000 do
    begin
      Insert(i, a, 50);
      Delete(a, 50, 1);
    end;
    Chk(17, (Length(a) = 100) and (a[50] = 50) and (a[99] = 99));
  end;
end;

{ ---- string Insert/Delete unaffected ---- }
procedure StringForms;
var s: string;
begin
  s := 'hello world';
  Delete(s, 1, 6);
  Insert('X', s, 3);
  Chk(18, s = 'woXrld');
end;

{ ---- expression args (eval once, source order) ---- }
function Idx: Integer;
begin
  Idx := 1;
end;
procedure ExprArgs;
var a: array of Integer;
begin
  Insert(2 + 3, a, Idx - 1);
  Insert(Length(a) * 10, a, Idx);       { value reads the array being grown }
  Chk(19, (Length(a) = 2) and (a[0] = 5) and (a[1] = 10));
  Delete(a, Idx - 1, Idx);
  Chk(20, (Length(a) = 1) and (a[0] = 10));
end;

begin
  okCount := 0;
  DeleteBasics;
  InsertBasics;
  Doubles;
  RecDelete;
  Churn(false);
  Churn(true);
  Churn(false);
  StringForms;
  ExprArgs;
  writeln('total ok ', okCount, ' / 20');
end.
