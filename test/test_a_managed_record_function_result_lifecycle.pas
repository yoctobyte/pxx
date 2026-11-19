program test_a_managed_record_function_result_lifecycle;
{ A function returning a record with Initialize/Finalize, against fpc 3.2.2.
  bug-a-a-managed-record-function-result-runs-neither-initialize-nor-finalize

  The CALLER owns a temp for a result that is not stored straight into a
  variable: Initialize at routine entry, Finalize at exit, one temp per record
  type, reused from statement to statement. The callee's Result starts as that
  temp, or, for `x := Make`, as x's old value (fpc passes x itself), so
  `Result.id was` prints 0 and then 20, as in fpc.

  Byte-identical to fpc 3.2.2 except two lines. Both are fpc temp-allocation
  details, not a lifetime that pxx gets wrong:
    - P3: fpc Finalizes a DISCARDED result's temp twice, once at the end of
      the statement and again at routine exit, after one Initialize. pxx
      Finalizes it once, at exit.
    - Meth: two calls in ONE statement. fpc reuses one temp inside the
      statement and pxx keeps two, so `live=` reads 3 where fpc reads 2. Both
      are back to 1 afterwards. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
uses SysUtils;
type
  TFoo = record
    id: Integer; pad1, pad2, pad3: Int64;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TCnt = record
    id: Integer;
    class operator Initialize(var a: TCnt);
    class operator Finalize(var a: TCnt);
  end;
  TStrRec = record
    s: AnsiString; n: Integer;
    class operator Initialize(var a: TStrRec);
    class operator Finalize(var a: TStrRec);
  end;
  TOuter = record
    tag: Integer;
    inner: TCnt;
  end;
  TMaker = class
    function Get(k: Integer): TCnt;
  end;
var n: Integer = 0;
    live: Integer = 0;
class operator TFoo.Initialize(var a: TFoo); begin a.id := 0; WriteLn('  Init'); end;
class operator TFoo.Finalize(var a: TFoo);   begin WriteLn('  Fin id=', a.id); end;
class operator TCnt.Initialize(var a: TCnt); begin a.id := 0; Inc(live); end;
class operator TCnt.Finalize(var a: TCnt);   begin Dec(live); end;
class operator TStrRec.Initialize(var a: TStrRec); begin a.n := -1; Inc(live); end;
class operator TStrRec.Finalize(var a: TStrRec);   begin Dec(live); end;

function Make: TFoo; begin Inc(n); WriteLn('  Make body, Result.id was ', Result.id); Result.id := 10 * n; end;
procedure TakeConst(const f: TFoo); begin WriteLn('  callee id=', f.id); end;
procedure P1; begin WriteLn('P1 arg'); TakeConst(Make); WriteLn('P1 end'); end;
procedure P2; var x: TFoo; begin WriteLn('P2 assign'); x := Make; WriteLn('  x.id=', x.id); x := Make; WriteLn('  x.id=', x.id); WriteLn('P2 end'); end;
procedure P3; begin WriteLn('P3 discard'); Make; WriteLn('P3 end'); end;

function MakeCnt(k: Integer): TCnt; begin Result.id := k; end;
function MakeStr(k: Integer): TStrRec; begin Result.s := 'v' + IntToStr(k); Result.n := k; end;
function MakeOuter(k: Integer): TOuter; begin Result.tag := k; Result.inner.id := k * 2; end;
function TMaker.Get(k: Integer): TCnt; begin Result.id := k + 100; end;
function Id(const f: TCnt): Integer; begin Result := f.id; end;
function Boom(k: Integer): TCnt; begin Result.id := k; if k = 3 then raise Exception.Create('boom'); end;
function Pair(const a, b: TCnt): Integer; begin Result := a.id * 10 + b.id; end;

procedure Loop;
var i, sum: Integer;
begin
  sum := 0;
  for i := 1 to 5 do sum := sum + Id(MakeCnt(i));
  WriteLn('loop sum=', sum, ' live=', live);
end;
procedure Strs;
var i: Integer; r: TStrRec;
begin
  for i := 1 to 3 do begin r := MakeStr(i); Write(r.s, ':', r.n, ' '); end;
  WriteLn(Length(MakeStr(42).s), ' live=', live);
end;
procedure Outer;
var o: TOuter;
begin
  o := MakeOuter(4); WriteLn('outer ', o.tag, ' ', o.inner.id, ' ', MakeOuter(5).inner.id, ' live=', live);
end;
procedure Meth;
var m: TMaker;
begin
  m := TMaker.Create; WriteLn('meth ', Id(m.Get(1)), ' ', m.Get(2).id, ' live=', live); m.Free;
end;
procedure Exc;
var i: Integer;
begin
  try
    for i := 1 to 5 do WriteLn('exc ', Id(Boom(i)));
  except on E: Exception do WriteLn('caught ', E.Message, ' live=', live); end;
end;
procedure TwoInOne;
begin
  { two results alive at once in one expression: two temps, never one }
  WriteLn('pair ', Pair(MakeCnt(3), MakeCnt(4)));
  WriteLn('pair ', Pair(MakeCnt(5), MakeCnt(6)));
end;

begin
  P1; P2; P3;
  Loop; WriteLn('after loop live=', live);
  Strs; WriteLn('after strs live=', live);
  Outer; WriteLn('after outer live=', live);
  Meth; WriteLn('after meth live=', live);
  Exc; WriteLn('after exc live=', live);
  TwoInOne; WriteLn('after pair live=', live);
  WriteLn('main ', Id(MakeCnt(9)), ' live=', live);
end.
