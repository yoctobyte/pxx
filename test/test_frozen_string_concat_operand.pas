program test_frozen_string_concat_operand;
{ A FROZEN-string operand of `+` is a string, whichever frozen kind produced it.
  A call carries its result's STORAGE kind (Procs[].RetType), so `P + '!'` with
  `P: shortstring` arrived at the additive arms as tyShortString, missed the
  concat arm (which tests tyString / tyAnsiString / tyChar) and fell into
  POINTER ARITHMETIC — `writeln(P + '!')` printed an address, `a := P + '!'`
  gave the empty string. The same concat on a shortstring VARIABLE was right
  all along, which is what kept it hidden.
  bug-p-a-frozen-string-concat-operand-becomes-pointer-arithmetic }
{$mode objfpc}

type
  TStr8 = string[8];

function P: shortstring;
begin
  P := 'ab';
end;

function S8: TStr8;
begin
  S8 := 'cd';
end;

type
  TBox = class
    function Tag: shortstring;
  end;

function TBox.Tag: shortstring;
begin
  Tag := 'box';
end;

var
  v: shortstring;
  a: ansistring;
  b: TBox;
  i: Integer;
begin
  v := 'ab';
  writeln('a ', v + '!');            { the variable path, which always worked }
  writeln('b ', P + '!');
  writeln('c ', '<' + P + '>');
  writeln('d ', P + S8);
  writeln('e ', P + v);
  a := P + '!';
  writeln('f ', a, '|', Length(a));
  b := TBox.Create;
  writeln('g ', b.Tag + '!');
  b.Free;
  { in a loop, so a stack-carving concat would show up as an overflow }
  a := '';
  for i := 1 to 200 do a := a + P;
  writeln('h ', Length(a));
  writeln('OK');
end.
