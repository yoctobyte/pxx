program test_shortstring_function_result;
{ A function whose result type is a FROZEN string — `shortstring`, or the sized
  `string[N]` — is a string VALUE like any other. It was not: a call carries its
  result's STORAGE kind (Procs[].RetType), while only a symbol read is passed
  through StrValTk's value-kind normalisation, so the write dispatch's
  `= tyString` test missed it and the expression fell through to the INTEGER
  arm. `writeln(P)` printed the struct pointer (4304016) where FPC prints `ab`.
  Silently wrong output, no diagnostic.
  bug-p-a-shortstring-function-result-prints-as-a-pointer }
{$mode objfpc}

type
  TStr8 = string[8];   { FPC refuses a local `string[N]` in a result type }

function P: shortstring;
begin
  P := 'ab';
end;

function S8: TStr8;
begin
  S8 := 'sized';
end;

function F(n: Integer): shortstring;
begin
  F := 'q';
  if n > 1 then F := 'qq';
end;

function Mutated: shortstring;
begin
  Result := 'cd';
  Result[1] := 'X';
end;

type
  TBox = class
    function Tag: shortstring;
  end;

function TBox.Tag: shortstring;
begin
  Tag := 'boxed';
end;

var
  b: TBox;
  t: shortstring;
begin
  writeln('a ', P);
  writeln('b ', S8);
  writeln('c ', F(1), '|', F(2));
  writeln('d ', Mutated);
  { the paths that already worked, kept as a guard against fixing one by
    breaking the other: assignment out of the result, and length/compare. }
  t := P;
  writeln('e ', t, '|', Length(t), '|', Length(P));
  writeln('f ', P = 'ab', '|', P = 'zz');
  { …and a METHOD result, which reaches the same write dispatch by a different
    parser path. }
  b := TBox.Create;
  writeln('g ', b.Tag);
  b.Free;
  { field width on a frozen-string value }
  writeln('h |', P:5, '|');
  writeln('OK');
end.
