{ A string literal standing in for the element list of an `array[..] of Char`.

  Ordinary Pascal: a char array is a fixed-width field, so a SHORT literal has a
  defined remainder (spaces) and a LONG one has nowhere to go. Every row here is
  fpc 3.2.2's own output, byte for byte.

  Three rows are CONTROLS that passed before the fix and must keep passing:
  `single chars` in both the 1-D and the 2-D spelling (the element list has
  always worked, so a fix that swallowed it would be a regression, not progress)
  and `named T sizeof`, which is the row that made this a defect and not a
  missing feature -- `const a: array[1..3] of T` reported SizeOf 12 for a 9-byte
  object at HEAD, with no diagnostic, because the const path was the one
  declaration path that never learned to merge a named array element's
  dimensions. The refusal in the ticket could not be fixed without that, since
  there is no row to fill if the compiler does not know the row is three chars.

  The rows print ELEMENTS, never `writeln(a[1])` of a whole row: partially
  subscripting an N-D char array yields a scalar rather than a row at HEAD,
  which is a separate open defect and would have put a known-red row in a file
  that is meant to be about initialisers. }
program test_char_array_string_init;

type
  TA4 = array[1..4] of Char;
  TRow3 = array[1..3] of Char;

const
  cs = 'ABCD';

  c1  : array[1..4] of Char = 'ABCD';
  c1n : TA4                 = 'ABCD';
  c1s : array[1..4] of Char = 'AB';
  c1e : array[1..4] of Char = '';
  c1c : array[1..4] of Char = cs;
  c1l : array[1..4] of Char = ('A', 'B', 'C', 'D');
  c2  : array[1..2, 1..3] of Char = ('abc', 'def');
  c2s : array[1..2, 1..3] of Char = ('a', 'de');
  c2l : array[1..2, 1..3] of Char = (('a', 'b', 'c'), ('d', 'e', 'f'));
  cT  : array[1..2] of TRow3 = ('abc', 'def');
  c3  : array[1..2, 1..2, 1..3] of Char = (('abc', 'def'), ('ghi', 'jkl'));

var
  v1  : array[1..4] of Char = 'WXYZ';
  v1s : array[1..4] of Char = 'W';
  v2  : array[1..2, 1..3] of Char = ('uvw', 'xyz');
  vT  : array[1..3] of TRow3 = ('asd', 'sdf', 'ddf');

procedure Row1(const nm: ShortString; a, b, c, d: Char);
begin
  writeln(nm, ': [', a, b, c, d, ']');
end;

procedure Row2(const nm: ShortString; a, b, c, d, e, f: Char);
begin
  writeln(nm, ': [', a, b, c, '|', d, e, f, ']');
end;

begin
  Row1('const literal      ', c1[1], c1[2], c1[3], c1[4]);
  Row1('const named type   ', c1n[1], c1n[2], c1n[3], c1n[4]);
  Row1('const short (pad)  ', c1s[1], c1s[2], c1s[3], c1s[4]);
  Row1('const empty (pad)  ', c1e[1], c1e[2], c1e[3], c1e[4]);
  Row1('const from a const ', c1c[1], c1c[2], c1c[3], c1c[4]);
  Row1('CONTROL single char', c1l[1], c1l[2], c1l[3], c1l[4]);
  Row2('const 2-D rows     ', c2[1][1], c2[1][2], c2[1][3], c2[2][1], c2[2][2], c2[2][3]);
  Row2('const 2-D short    ', c2s[1][1], c2s[1][2], c2s[1][3], c2s[2][1], c2s[2][2], c2s[2][3]);
  Row2('CONTROL 2-D chars  ', c2l[1][1], c2l[1][2], c2l[1][3], c2l[2][1], c2l[2][2], c2l[2][3]);
  Row2('const named T rows ', cT[1][1], cT[1][2], cT[1][3], cT[2][1], cT[2][2], cT[2][3]);
  Row2('const 3-D rows     ', c3[1][1][1], c3[1][2][1], c3[2][1][1], c3[2][2][1], c3[2][2][2], c3[2][2][3]);
  Row1('var literal        ', v1[1], v1[2], v1[3], v1[4]);
  Row1('var short (pad)    ', v1s[1], v1s[2], v1s[3], v1s[4]);
  Row2('var 2-D rows       ', v2[1][1], v2[1][2], v2[1][3], v2[2][1], v2[2][2], v2[2][3]);
  Row2('var named T rows   ', vT[1][1], vT[1][2], vT[1][3], vT[3][1], vT[3][2], vT[3][3]);
  writeln('CONTROL named T sizeof: ', SizeOf(cT), ' ', SizeOf(vT), ' ', SizeOf(c2));
  writeln('CONTROL 1-D whole write: [', c1, ']');
end.
