program IndexSlice;

{ Slice 3: indexing a managed string, and SetLength.

  Both need the SLOT's address, which is why they arrive together — they are
  the two write positions the old IR_LEA read-only answer was built on top of.
  The shapes that matter are not "does s[1] read the right byte" (a diff finds
  that) but the ones where a wrong lowering still produces plausible output:

    * COW. `t := s; s[1] := 'z'` must leave t alone. A write that skips
      PXXStrUnique edits the shared block and t changes too — and the program
      keeps running.
    * The slot, not the handle. A write through the HANDLE where the slot
      address belongs stores a character over the first byte of the string's
      own characters, or a heap pointer over them for SetLength.
    * The index is a READ inside a write. `b[Length(b)] := c` evaluates
      Length against the base; under a leaked write flag that reads the SLOT.
    * Non-scalar bases. A managed string that is itself a record field or an
      array element is a slot address in BOTH positions, so the read case
      needs its own load — the bug riscv32 and arm32 each shipped. }

type
  TRec = record
    a: string;
    n: Integer;
    b: string;
  end;

var
  s, t, u: string;
  r: TRec;
  arr: array[0..2] of string;
  i: Integer;
  c: Char;

procedure FillVar(var v: string);
begin
  SetLength(v, 3);
  v[1] := 'V';
  v[2] := 'a';
  v[3] := 'r';
end;

function ReadVar(var v: string): Char;
begin
  ReadVar := v[2];
end;

function Reverse(const src: string): string;
var k, n: Integer;
begin
  n := Length(src);
  Reverse := '';
  SetLength(Reverse, n);
  k := 1;
  while k <= n do
  begin
    Reverse[k] := src[n - k + 1];
    k := k + 1;
  end;
end;

begin
  { --- read, scalar --- }
  s := 'abcdef';
  writeln(s[1], s[3], s[6], '|', Length(s));

  { --- read in a loop, and the index is an expression --- }
  u := '';
  i := 1;
  while i <= Length(s) do
  begin
    u := u + s[Length(s) - i + 1];
    i := i + 1;
  end;
  writeln(u);

  { --- write, scalar, unshared --- }
  s := 'abcdef';
  s[1] := 'Z';
  s[6] := 'Y';
  writeln(s, '|', Length(s));

  { --- COW: the assertion this slice exists for --- }
  s := 'shared';
  t := s;
  s[1] := 'X';
  writeln(s, '|', t);

  { --- and the other direction: writing through the copy --- }
  s := 'shared';
  t := s;
  t[6] := 'X';
  writeln(s, '|', t);

  { --- the index is a READ even when the whole thing is a write target --- }
  s := 'abcd';
  s[Length(s)] := '!';
  s[Length(s) - 2] := '?';
  writeln(s);

  { --- a record field: a slot address in both positions --- }
  r.a := 'field-a';
  r.n := 7;
  r.b := 'field-b';
  writeln(r.a[1], r.b[7], '|', r.n);
  r.a[1] := 'F';
  r.b[7] := 'B';
  writeln(r.a, '|', r.b, '|', r.n);

  { --- an array element: likewise --- }
  arr[0] := 'zero';
  arr[1] := 'one';
  arr[2] := 'two';
  writeln(arr[0][1], arr[1][1], arr[2][1]);
  arr[1][1] := 'O';
  writeln(arr[0], '|', arr[1], '|', arr[2]);

  { --- a var parameter: the frame slot holds the CALLER's slot address --- }
  s := 'wiped';
  FillVar(s);
  writeln(s, '|', Length(s), '|', ReadVar(s));

  { --- SetLength: grow, shrink, to zero, and back --- }
  s := 'abcdef';
  SetLength(s, 3);
  writeln(s, '|', Length(s));
  SetLength(s, 6);
  writeln(Length(s), '|', Ord(s[6]));
  s := 'abc';
  SetLength(s, 0);
  writeln('[', s, ']', '|', Length(s));
  SetLength(s, 2);
  s[1] := 'o';
  s[2] := 'k';
  writeln(s, '|', Length(s));

  { --- SetLength on a SHARED string publishes into one slot only --- }
  s := 'sharedlen';
  t := s;
  SetLength(s, 4);
  writeln(s, '|', t, '|', Length(s), '|', Length(t));

  { --- SetLength on a record field --- }
  r.a := 'longfield';
  r.n := 11;
  SetLength(r.a, 4);
  writeln(r.a, '|', Length(r.a), '|', r.n, '|', r.b);

  { --- SetLength on an array element --- }
  arr[2] := 'truncate';
  SetLength(arr[2], 4);
  writeln(arr[1], '|', arr[2], '|', Length(arr[2]));

  { --- the two together, in a function whose result is managed --- }
  writeln(Reverse('stressed'), '|', Reverse(''), '|', Reverse('a'));

  { --- VARIABLE indices, on both sides and on a nested base. A constant index
        can fold into the address; a variable one cannot, and the two reach the
        managed-base check by different routes. --- }
  arr[0] := 'alpha';
  arr[1] := 'bravo';
  arr[2] := 'delta';
  i := 1;
  arr[i][i + 1] := '#';
  writeln(arr[0], '|', arr[1], '|', arr[2]);
  i := 2;
  SetLength(arr[i], 3);
  writeln(arr[i], '|', Length(arr[i]));
  s := '';
  i := 0;
  while i <= 2 do
  begin
    s := s + arr[i][1];
    i := i + 1;
  end;
  writeln(s);

  { --- COW in a loop: shared every iteration, so PXXStrUnique clones every
        iteration. A write that skipped it would edit t and print the wrong
        line here even though the single-shot case above passed. --- }
  t := 'wxyz';
  i := 1;
  while i <= 4 do
  begin
    u := t;
    u[i] := '*';
    write(u, ' ');
    i := i + 1;
  end;
  writeln('|', t);

  { --- a Char round-trip through a variable index --- }
  s := 'abc';
  c := s[2];
  s[2] := s[3];
  s[3] := c;
  writeln(s);
end.
