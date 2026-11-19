program test_dynarray_value_into_scalar_ok;
{ The LEGAL neighbours of a refusal: a dynamic-array value stored where it
  belongs. Must compile and print the values below.

  `r := p` with `operator :=(a: TRecArr): TRec` declared must CALL the
  operator: the conversion rewrite skipped it because an array's kind is its
  element's (tyRecord into tyRecord), so pxx stored the raw handle and printed
  0 where fpc prints 30.
  bug-a-a-dynamic-array-value-can-be-assigned-to-a-record-variable }
{$mode objfpc}{$H+}
type
  TRec = record v: LongInt; end;
  TRecArr = array of TRec;
  TM = array of TRecArr;

operator := (a: TRecArr): TRec;
begin
  Result.v := Length(a) * 10;
end;

function Mk: TRecArr;
begin
  SetLength(Result, 2);
  Result[1].v := 5;
end;

var
  p, q: TRecArr;
  m: TM;
  r: TRec;
  pp: Pointer;
  ca: array of Char;
  s: AnsiString;
begin
  SetLength(p, 3);
  r := p;                       { conversion operator }
  WriteLn('conv ', r.v);
  p[0].v := 7;
  q := p + p;                   { array into array }
  r := q[3];                    { element into record }
  WriteLn('elem ', r.v, ' ', Length(q));
  SetLength(m, 1);
  m[0] := Mk;
  r := m[0][1];
  WriteLn('nested ', r.v);
  r := Mk[1];
  WriteLn('call ', r.v);
  pp := p;                      { a Pointer may hold the handle }
  p := nil;
  p := TRecArr(pp);
  WriteLn('ptr ', Length(p));
  SetLength(ca, 2); ca[0] := 'h'; ca[1] := 'i';
  s := ca;                      { pxx extension: array of Char builds an AnsiString }
  WriteLn('str ', s);
end.
