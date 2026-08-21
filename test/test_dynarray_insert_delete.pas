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

{ ---- non-managed record elements: Delete + Insert (memory-copied gap) ---- }
type TPt = record x, y: Integer; end;
type TDay = (dMo, dTu, dWe, dTh, dFr);
type TDays = set of TDay;
procedure RecDelete;
var r: array of TPt; i: Integer; p: TPt;
begin
  SetLength(r, 3);
  for i := 0 to 2 do begin r[i].x := i; r[i].y := i * 100; end;
  Delete(r, 1, 1);
  Chk(16, (Length(r) = 2) and (r[0].x = 0) and (r[1].x = 2) and (r[1].y = 200));
  p.x := 9; p.y := 900;
  Insert(p, r, 1);
  Chk(27, (Length(r) = 3) and (r[1].x = 9) and (r[1].y = 900) and (r[2].x = 2));
  Insert(r[0], r, 3);                   { self-referencing record value }
  Chk(28, (Length(r) = 4) and (r[3].x = 0) and (r[3].y = 0));
end;

{ ---- managed-field record elements: field-walk retain via layout desc ---- }
type TMRec = record
  Name: AnsiString;
  Id: Integer;
end;
procedure ManagedRecElems;
var m: array of TMRec; v: TMRec; k: Integer;
begin
  SetLength(m, 4);
  for k := 0 to 3 do
  begin
    m[k].Name := 'n' + Chr(48 + k);   { concat: unique heap handles }
    m[k].Id := k;
  end;
  Delete(m, 1, 2);
  Chk(31, (Length(m) = 2) and (m[0].Name = 'n0') and (m[1].Name = 'n3') and (m[1].Id = 3));
  v.Name := 'ins' + 'erted';
  v.Id := 99;
  Insert(v, m, 1);
  Chk(32, (Length(m) = 3) and (m[1].Name = 'inserted') and (m[1].Id = 99));
  Insert(m[0], m, 3);                  { self-referencing record value }
  Chk(33, (Length(m) = 4) and (m[3].Name = 'n0') and (m[3].Id = 0));
  Delete(m, 0, Length(m));
  Chk(34, Length(m) = 0);
  { churn: field refcounts must balance across the fresh-temp rebuilds }
  SetLength(m, 2);
  m[0].Name := 'x' + 'a'; m[0].Id := 1;
  m[1].Name := 'y' + 'b'; m[1].Id := 2;
  for k := 1 to 500 do
  begin
    v.Name := 'c' + Chr(48 + (k mod 10));
    v.Id := k;
    Insert(v, m, 1);
    Delete(m, 1, 1);
  end;
  Chk(35, (Length(m) = 2) and (m[0].Name = 'xa') and (m[1].Name = 'yb') and (v.Name = 'c0'));
end;

{ ---- set elements: Insert (32-byte memory copy) ---- }
procedure SetElems;
var ds: array of TDays; d: TDays;
begin
  d := [dMo, dWe];
  Insert(d, ds, 0);
  d := [dFr];
  Insert(d, ds, 1);
  Chk(29, (Length(ds) = 2) and (dWe in ds[0]) and not (dFr in ds[0]) and (dFr in ds[1]));
  Delete(ds, 0, 1);
  Chk(30, (Length(ds) = 1) and (dFr in ds[0]));
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

{ ---- AnsiString elements: FPC semantics + refcount balance ---- }
procedure ManagedElems;
var a: array of AnsiString; s: AnsiString; k: Integer;
begin
  SetLength(a, 3);
  a[0] := 'alpha'; a[1] := 'beta' + 'X'; a[2] := 'gamma';
  Delete(a, 1, 1);
  Chk(21, (Length(a) = 2) and (a[0] = 'alpha') and (a[1] = 'gamma'));
  s := 'ins' + 'erted';
  Insert(s, a, 1);
  Chk(22, (Length(a) = 3) and (a[1] = 'inserted'));
  Insert('lit', a, 0);
  Insert(a[3], a, 4);                   { value reads the array itself }
  Chk(23, (Length(a) = 5) and (a[0] = 'lit') and (a[4] = 'gamma'));
  Delete(a, 0, 99);
  Chk(24, Length(a) = 0);
  Insert('solo', a, 0);
  Chk(25, (Length(a) = 1) and (a[0] = 'solo') and (s = 'inserted'));
  { churn: per-pass fresh-temp refcounts must balance (the SetLength(temp,0)
    pre-empty — without it PXXDynSetLen's copy+retain of the previous pass's
    elements leaked one ref per kept element per op) }
  SetLength(a, 20);
  for k := 0 to 19 do a[k] := 'item' + Chr(65 + k);
  for k := 1 to 500 do
  begin
    Insert('mid' + Chr(65 + (k mod 26)), a, 10);
    Delete(a, 10, 1);
  end;
  Chk(26, (Length(a) = 20) and (a[0] = 'itemA') and (a[19] = 'itemT'));
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

{ ---- FPC's array-SPLICE Insert(srcArr, arr, index) ---- }
{ Before this form existed the splice compiled as the ONE-ELEMENT Insert and
  stored the source array's HANDLE as if it were an element: two `array of
  Integer` printed `10 <garbage> 11 12` where FPC prints `10 90 91 11 12`.
  Silent wrong output, which is why the mismatched-element-type case is now a
  compile error rather than something plausible. Every expectation below is
  FPC 3.2.2's own output. }
procedure SpliceInts;
var a, b: array of Integer; idx: Integer;
begin
  { the whole clamping range: below 0, inside, past the end }
  SetLength(a, 3); a[0] := 10; a[1] := 11; a[2] := 12;
  SetLength(b, 2); b[0] := 90; b[1] := 91;
  Insert(b, a, -2);
  Chk(36, (Length(a) = 5) and (a[0] = 90) and (a[1] = 91) and (a[2] = 10) and (a[4] = 12));
  SetLength(a, 3); a[0] := 10; a[1] := 11; a[2] := 12;
  Insert(b, a, 1);
  Chk(37, (Length(a) = 5) and (a[0] = 10) and (a[1] = 90) and (a[2] = 91) and
          (a[3] = 11) and (a[4] = 12));
  SetLength(a, 3); a[0] := 10; a[1] := 11; a[2] := 12;
  Insert(b, a, 99);
  Chk(38, (Length(a) = 5) and (a[2] = 12) and (a[3] = 90) and (a[4] = 91));
  { an empty source inserts nothing; an empty destination becomes the source }
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  SetLength(b, 0);
  Insert(b, a, 1);
  Chk(39, (Length(a) = 3) and (a[0] = 1) and (a[2] = 3));
  SetLength(a, 0);
  SetLength(b, 2); b[0] := 7; b[1] := 8;
  Insert(b, a, 0);
  Chk(40, (Length(a) = 2) and (a[0] = 7) and (a[1] = 8));
  { self-splice: the old buffer stays intact until the handle swap, so the
    source is still readable while the fresh one is being filled }
  SetLength(a, 3); a[0] := 4; a[1] := 5; a[2] := 6;
  Insert(a, a, 1);
  Chk(41, (Length(a) = 6) and (a[0] = 4) and (a[1] = 4) and (a[2] = 5) and
          (a[3] = 6) and (a[4] = 5) and (a[5] = 6));
end;

procedure SpliceManaged;
var sa, sb: array of AnsiString; i, k: Integer;
begin
  SetLength(sa, 3); sa[0] := 'aa'; sa[1] := 'bb'; sa[2] := 'cc';
  SetLength(sb, 2); sb[0] := 'XX'; sb[1] := 'YY';
  Insert(sb, sa, 0);
  Chk(42, (Length(sa) = 5) and (sa[0] = 'XX') and (sa[1] = 'YY') and (sa[2] = 'aa'));
  SetLength(sa, 3); sa[0] := 'aa'; sa[1] := 'bb'; sa[2] := 'cc';
  Insert(sb, sa, 1);
  Chk(43, (Length(sa) = 5) and (sa[0] = 'aa') and (sa[1] = 'XX') and
          (sa[2] = 'YY') and (sa[3] = 'bb') and (sa[4] = 'cc'));
  SetLength(sa, 3); sa[0] := 'aa'; sa[1] := 'bb'; sa[2] := 'cc';
  Insert(sb, sa, 3);
  Chk(44, (Length(sa) = 5) and (sa[3] = 'XX') and (sa[4] = 'YY'));
  SetLength(sa, 2); sa[0] := 'p'; sa[1] := 'q';
  Insert(sa, sa, 1);
  Chk(45, (Length(sa) = 4) and (sa[0] = 'p') and (sa[1] = 'p') and
          (sa[2] = 'q') and (sa[3] = 'q'));
  { churn: the inserted elements are retained by the fresh buffer along with
    the kept ones, so 20000 splices neither leak nor double-free }
  SetLength(sb, 2); sb[0] := 'z1'; sb[1] := 'z2';
  k := 0;
  for i := 1 to 20000 do
  begin
    SetLength(sa, 1); sa[0] := 'head';
    Insert(sb, sa, 1);
    k := k + Length(sa) + Length(sa[2]);
  end;
  Chk(46, (k = 100000) and (sa[0] = 'head') and (sa[1] = 'z1') and (sa[2] = 'z2'));
end;

procedure SpliceRecsAndSets;
var
  ma, mb: array of TMRec;
  ra, rb: array of TPt;
  qa, qb: array of TDays;
begin
  SetLength(ma, 2); ma[0].Id := 1; ma[0].Name := 'one'; ma[1].Id := 2; ma[1].Name := 'two';
  SetLength(mb, 1); mb[0].Id := 9; mb[0].Name := 'nine';
  Insert(mb, ma, 1);
  Chk(47, (Length(ma) = 3) and (ma[0].Name = 'one') and (ma[1].Name = 'nine') and
          (ma[1].Id = 9) and (ma[2].Name = 'two'));
  SetLength(ra, 2); ra[0].x := 1; ra[0].y := 2; ra[1].x := 3; ra[1].y := 4;
  SetLength(rb, 1); rb[0].x := 8; rb[0].y := 9;
  Insert(rb, ra, 1);
  Chk(48, (Length(ra) = 3) and (ra[1].x = 8) and (ra[1].y = 9) and (ra[2].x = 3));
  SetLength(qa, 2); qa[0] := [dMo, dTu]; qa[1] := [dWe];
  SetLength(qb, 1); qb[0] := [dTh, dFr];
  Insert(qb, qa, 1);
  Chk(49, (Length(qa) = 3) and (dMo in qa[0]) and (dTh in qa[1]) and (dFr in qa[1]) and
          (dWe in qa[2]) and not (dTh in qa[0]));
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
  ManagedElems;
  ManagedRecElems;
  SetElems;
  SpliceInts;
  SpliceManaged;
  SpliceRecsAndSets;
  writeln('total ok ', okCount, ' / 49');
end.
