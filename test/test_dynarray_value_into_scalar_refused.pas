program test_dynarray_value_into_scalar_refused;
{ EIGHT stores of a dynamic-array value into a destination that can never hold
  one. Each compiled before 2026-11-19 and stored the array HANDLE: `i := ia`
  printed a heap address, the record cases read through the handle, and an
  array of Char into a frozen string printed blanks at the full capacity. fpc
  3.2.2 refuses all eight (seven as `Incompatible types: got "TRecArr" expected
  "TRec"`, the concatenation earlier as an undeclared operator). The row counts
  the refusals, so a shape that slips back
  to a silent accept goes red.
  bug-a-a-dynamic-array-value-can-be-assigned-to-a-record-variable }
{$mode objfpc}{$H+}
type
  TRec = record v: LongInt; end;
  TRecArr = array of TRec;
  TM = array of TRecArr;

function Mk: TRecArr;
begin
  SetLength(Result, 1);
end;

var
  p, q: TRecArr;
  m: TM;
  r: TRec;
  ia: array of LongInt;
  i: LongInt;
  d: Double;
  s: AnsiString;
  ss: ShortString;
  ca: array of Char;
begin
  r := p + q;     { 1: the ticket's concatenation }
  r := p;         { 2: a plain array variable }
  r := m[0];      { 3: one level of a nested array }
  r := Mk;        { 4: a function result }
  i := ia;        { 5: into an integer }
  d := ia;        { 6: into a float }
  s := ia;        { 7: a non-char array into an AnsiString }
  ss := ca;       { 8: array of Char into a frozen string }
end.
