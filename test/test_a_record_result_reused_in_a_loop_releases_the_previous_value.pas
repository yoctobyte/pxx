{ A function returning a record with a managed field, called in a LOOP, hands
  its result through one hidden destination temp that every iteration reuses.
  The callee's copy-out must release the previous value's managed fields first,
  or each iteration after the first orphans them. xtensa alone skipped that
  release: pin v437 prints 176 B/call for both loops and 304 for Parse here,
  on Call0 and windowed alike. Parse is the TBig loop in PXXPromoFromStr, which
  is how NilPy int("25") / int("200") leaked 192 B per call on an ESP32-S3.
  Every row must print 0, on every target. }
program test_a_record_result_reused_in_a_loop_releases_the_previous_value;

type
  TB = record
    neg: Boolean;
    limbs: array of Int64;
    tag: AnsiString;
  end;

function FromInt(v: Int64): TB;
var r: TB;
begin
  r.neg := v < 0;
  SetLength(r.limbs, 1);
  r.limbs[0] := v;
  r.tag := Copy('tagged', 1, 3 + Ord(v < 0));
  FromInt := r;
end;

function Mul(const a, b: TB): TB;
var r: TB;
begin
  r.neg := False;
  SetLength(r.limbs, 1);
  if Length(a.limbs) > 0 then r.limbs[0] := a.limbs[0] * b.limbs[0]
  else r.limbs[0] := 0;
  Mul := r;
end;

function Add(const a, b: TB): TB;
var r: TB;
begin
  r.neg := False;
  SetLength(r.limbs, 1);
  r.limbs[0] := a.limbs[0] + b.limbs[0];
  Add := r;
end;

function Parse(const s: AnsiString): Int64;
var r, ten: TB; i: Integer;
begin
  SetLength(r.limbs, 0);
  r.neg := False;
  ten := FromInt(10);
  for i := 1 to Length(s) do
    r := Add(Mul(r, ten), FromInt(Ord(s[i]) - 48));
  Parse := r.limbs[0];
end;

{ straight-line: each call has its own temp, so this was always flat }
procedure Straight;
var r: TB;
begin
  r := FromInt(1);
  r := FromInt(2);
end;

procedure ForLoop;
var r: TB; i: Integer;
begin
  for i := 1 to 3 do r := FromInt(i);
end;

procedure WhileLoop;
var r: TB; i: Integer;
begin
  i := 1;
  while i <= 3 do begin r := FromInt(i); Inc(i); end;
end;

var x: Int64;

procedure Row(const name: AnsiString; k: Integer);
var j: Integer; h0: Int64;
begin
  h0 := GetFPCHeapStatus.CurrHeapUsed;
  for j := 1 to 500 do
    case k of
      1: Straight;
      2: ForLoop;
      3: WhileLoop;
      4: x := Parse('200');
    end;
  WriteLn(name, ' bytes/call=', (Int64(GetFPCHeapStatus.CurrHeapUsed) - h0) div 500);
end;

begin
  Row('straight', 1);
  Row('for-loop', 2);
  Row('while-loop', 3);
  Row('parse', 4);
  WriteLn('parse=', Parse('200'), ' ', Parse('25'));
end.
