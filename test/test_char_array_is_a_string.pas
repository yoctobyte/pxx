{ A static `array[lo..hi] of Char` IS a string in FPC, in both directions, and
  pxx treated it as a bare Char in every string context. The arrayness lives on
  the SYMBOL (Syms[].IsArray/ArrLen) while the AST node for `a` is typed tyChar,
  so each context did something defensible and silently wrong:

    a := 'abcdefgh'   stored the low byte of the literal's HANDLE into a[0]
    s := a            answered ''
    a = 'abcdefgh'    False
    a + '!'           one garbage character, then '!'
    Write(a)          one garbage character

  Only array-to-array copy worked. The RTL had already routed around the gap --
  lib/rtl/palparallel.pas spells its two path constants one character at a time
  -- which is what kept it out of the corpus.

  The conversion is NOT a memcpy in the reading direction: FPC stops at the
  first #0 within the capacity, so an array[0..7] holding 'ABC'#0'EFGH' is the
  three-character 'ABC'. Writing pads: Min(Length(s), cap) characters then a
  zero fill. Every expectation below is `fpc -O- -Mobjfpc`'s.
  bug-p-a-char-array-is-not-a-string-in-any-direction }
program test_char_array_is_a_string;
{$mode objfpc}{$H+}

type
  TA8 = array[0..7] of Char;
  TA3 = array[1..3] of Char;

var
  a, a2: TA8; b: TA3; s: string;
  ok, total, i: Integer;

function Wrap(const q: string): string;
begin Wrap := '<' + q + '>'; end;

function WrapV(q: AnsiString): Integer;
begin WrapV := Length(q); end;

procedure Alias(var q: TA8);
begin q[0] := 'Z'; end;

procedure Chk(const what: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkS(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

procedure ChkBytes(const what: string; const q: array of Char; const want: array of Integer);
var k: Integer;
begin
  for k := 0 to High(want) do
    Chk(what + '[' + Chr(48 + k) + ']', Ord(q[Low(q) + k]), want[k]);
end;

begin
  ok := 0; total := 0;

  { string -> char array: exact, too long (truncates), too short (zero pads),
    embedded #0 (kept), empty (all zeros), and from a VARIABLE not a literal }
  a := 'abcdefgh';    ChkBytes('exact', a, [97,98,99,100,101,102,103,104]);
  a := 'abcdefghIJK'; ChkBytes('toolong', a, [97,98,99,100,101,102,103,104]);
  a := 'abc';         ChkBytes('short', a, [97,98,99,0,0,0,0,0]);
  a := 'ab'#0'cd';    ChkBytes('embnul', a, [97,98,0,99,100,0,0,0]);
  a := '';            ChkBytes('empty', a, [0,0,0,0,0,0,0,0]);
  s := 'zz'; a := s;  ChkBytes('fromvar', a, [122,122,0,0,0,0,0,0]);
  { a ONE-character literal is spelled tyChar and still pads }
  b := 'q';           ChkBytes('char1', b, [113,0,0]);
  b := 'xyz';         ChkBytes('b3', b, [120,121,122]);

  { char array -> string: stops at the first #0, else takes the whole capacity }
  for i := 0 to 7 do a[i] := Chr(65 + i);
  s := a;             ChkS('tostr full', s, 'ABCDEFGH');
  Chk('tostr len', Length(s), 8);
  a[3] := #0;
  s := a;             ChkS('tostr nul', s, 'ABC');
  Chk('tostr nul len', Length(s), 3);
  b := 'xyz'; s := b; ChkS('tostr b3', s, 'xyz');

  { comparison and concat go through the same conversion }
  Chk('eq short', Ord(a = 'ABC'), 1);
  Chk('eq full', Ord(a = 'ABC'#0'EFGH'), 0);
  Chk('neq', Ord(a <> 'ABC'), 0);
  Chk('lt', Ord(a < 'ABD'), 1);
  ChkS('concat', a + '!', 'ABC!');
  ChkS('concat left', '>' + a, '>ABC');
  b := 'xyz';
  a := 'xyz';
  Chk('arr vs arr', Ord(s = 'xyz'), 1);

  { array-to-array copy is untouched -- it was the one form that always worked }
  for i := 0 to 7 do a[i] := Chr(97 + i);
  a2 := a;            ChkBytes('arrcopy', a2, [97,98,99,100,101,102,103,104]);
  a2[0] := 'Z';
  Chk('arrcopy is a copy', Ord(a[0]), 97);

  { …and so is element access, which must not be dragged into the conversion }
  Chk('elem', Ord(a[2]), 99);
  a[2] := 'Q';
  Chk('elem store', Ord(a[2]), 81);

  { a `string` PARAMETER takes the conversion too -- and `Length` of the array
    itself is the ARRAY's length, 8, not a Char's 1 }
  a := 'hi';
  ChkS('const param', Wrap(a), '<hi>');
  Chk('value param', WrapV(a), 2);
  Chk('Length arr', Length(a), 8);
  Chk('Length b3', Length(b), 3);
  Chk('Low/High', Low(a) * 100 + High(a), 7);
  Chk('Pos', Pos('i', a), 2);
  ChkS('Copy', Copy(a, 1, 1), 'h');

  { a `var` parameter must NOT convert -- it aliases the array }
  Alias(a);
  Chk('var param aliases', Ord(a[0]), 90);
  Chk('var param keeps rest', Ord(a[1]), 105);

  writeln('total ok ', ok, ' / ', total);
  { Write of the array itself is the last row of the table }
  a := 'hi';
  writeln('write [', a, ']');
end.
