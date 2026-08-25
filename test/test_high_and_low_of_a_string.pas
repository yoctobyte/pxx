program test_high_and_low_of_a_string;
{ `High(s)` / `Low(s)` over a string, one row per string KIND.

  For `s: AnsiString = 'qxy'` fpc answers 1 and 3; pxx answered 0 and 2 — while
  `s[1]` is 'q' in both. pxx indexes strings from 1 exactly as fpc does, so
  0-based bounds were not a dialect choice but an inconsistency with pxx's own
  indexing: `for i := Low(s) to High(s) do Write(s[i])` read s[0] and dropped
  the last character. It compiled, it ran, it was wrong.

  Every fold above the tail is guarded on an array or an ordinal, so a string
  fell through to `Length(x) - 1` / `0` — the right answer for a 0-based dynamic
  array, inherited by strings by accident.

  There are THREE bases here, not two, and fpc gives all three:
    - a MANAGED string is 1 .. Length          (index 0 does not exist)
    - a FROZEN string is 0 .. declared CAPACITY (index 0 is the length byte,
      and the bound is the capacity, NOT the current length)
    - an ARRAY (incl. array of Char) is its own declared bounds
  The `walk` row is the point of the whole ticket; the rest keep the other two
  bases from being "fixed" into the first.

  KNOWN GAP, deliberately not asserted here: `High(G)` where G returns
  `string[6]` answers 1 (Length-1), fpc says 6. A frozen-string RESULT carries
  no capacity row (there is no ProcRetStrCap), and answering the 255 default
  would turn a too-small bound into a too-large one — a loop reading off the end
  instead of stopping early. Recorded on
  bug-p-high-and-low-of-a-string-are-off-by-one.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}{$H+}

type
  TSA = string[6];
  TBox = class
  public
    Tag: AnsiString;
  end;

function F: AnsiString;
begin Result := 'abcd'; end;

function CountUp(const p: AnsiString): Integer;
var i: Integer;
begin
  Result := 0;
  for i := Low(p) to High(p) do Inc(Result);
end;

var
  s, e: AnsiString;
  sh: string[10];
  ss: ShortString;
  a: TSA;
  ac: array[0..4] of Char;
  d: array of Integer;
  sa: array of AnsiString;
  r: record t: AnsiString; end;
  b: TBox;
  i: Integer;
  acc: AnsiString;
begin
  s := 'qxy'; e := ''; sh := 'pq'; ss := 'mno'; a := 'zz'; ac := 'wwwww';
  { the row the ticket is about }
  WriteLn('ansi    : ', Low(s), ' ', High(s));
  { …and what it is FOR: the canonical walk must cover the whole string }
  acc := '';
  for i := Low(s) to High(s) do acc := acc + s[i];
  WriteLn('walk    : ', acc);
  { an EMPTY managed string: High < Low, so the walk runs zero times }
  WriteLn('empty   : ', Low(e), ' ', High(e));
  acc := 'none';
  for i := Low(e) to High(e) do acc := 'ran';
  WriteLn('emptywalk: ', acc);
  { frozen strings: 0-based over the declared CAPACITY, not the length }
  WriteLn('short10 : ', Low(sh), ' ', High(sh));
  WriteLn('shortstr: ', Low(ss), ' ', High(ss));
  WriteLn('alias   : ', Low(a), ' ', High(a));
  { arrays keep their own bounds — the fix must not reach them }
  WriteLn('arrchar : ', Low(ac), ' ', High(ac));
  SetLength(d, 3);
  WriteLn('dynint  : ', Low(d), ' ', High(d));
  { …including a dyn array whose ELEMENT is a string, whose symbol carries
    tyAnsiString as its element type and would read as a string without the
    array guard }
  SetLength(sa, 4);
  WriteLn('dynstr  : ', Low(sa), ' ', High(sa));
  { a managed string reached through something other than a plain variable }
  r.t := 'mn';
  WriteLn('recfield: ', Low(r.t), ' ', High(r.t));
  b := TBox.Create;
  b.Tag := 'pqrst';
  WriteLn('objfield: ', Low(b.Tag), ' ', High(b.Tag));
  WriteLn('call    : ', Low(F), ' ', High(F));
  { …and through a const parameter, which is where library code writes it }
  WriteLn('param   : ', CountUp('hello'), ' ', CountUp(''));
  b.Free;
end.
