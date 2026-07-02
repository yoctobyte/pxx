program test_anonymous_record;
{ Anonymous (inline) record types — `var x: record ... end;` — legal ISO/FPC
  anywhere a type is expected (feature-anonymous-record-type). Parsed by
  ParseTypeKind's tkRecord/tkPacked case into an unnamed UCls row via the
  shared ParseRecordFields helper. Also pins the AddUField window-relocation
  fix: a NESTED anonymous record used to interleave its fields into the
  outer record's contiguous field window (outer fields resolved to the wrong
  slots). Var-param anon records are a pxx extension (FPC rejects the form
  in parameter lists). }
var
  okCount: Integer;
  x: record CodePos, DataOff: Integer; end;
  y: record a: Integer; s: string; end;
  arr: array[0..2] of record v, w: Integer; end;
  p: record n: Integer; sub: record q: Integer; end; end;
  pk: packed record a: Byte; b: Integer; end;
  vr: record case Integer of 0: (i: Int64); 1: (lo, hi: LongWord); end;
  i: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

procedure Fill(var r: record v, w: Integer; end);
begin r.v := 100; r.w := 200; end;

{ managed string field in a local anon record: ARC on scope exit, loop-safe }
function Churn: Integer;
var t: record s: string; n: Integer; end;
begin
  t.s := 'managed field ' + 'concat';
  t.n := Length(t.s);
  Churn := t.n;
end;

begin
  okCount := 0;
  x.CodePos := 7; x.DataOff := 9;
  Chk(1, (x.CodePos = 7) and (x.DataOff = 9) and (SizeOf(x) = 8));
  y.a := 1; y.s := 'hi';
  Chk(2, (y.a = 1) and (y.s = 'hi'));
  for i := 0 to 2 do begin arr[i].v := i; arr[i].w := i * 10; end;
  Chk(3, (arr[2].v = 2) and (arr[2].w = 20));
  p.n := 5; p.sub.q := 6;                 { nested anon: window-relocation pin }
  Chk(4, (p.n = 5) and (p.sub.q = 6));
  Chk(5, SizeOf(pk) = 5);                 { packed: 1 + 4 }
  vr.i := $1122334455667788;
  Chk(6, (vr.lo = $55667788) and (vr.hi = $11223344));  { case/variant overlay }
  Fill(arr[0]);
  Chk(7, (arr[0].v = 100) and (arr[0].w = 200));
  for i := 1 to 1000 do
    if Churn <> 20 then begin Chk(8, False); Halt(1); end;
  Chk(8, True);
  writeln('total ok ', okCount, ' / 8');
end.
