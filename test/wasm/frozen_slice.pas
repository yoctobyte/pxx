program FrozenSlice;
{ Frozen strings — string[N], ShortString, and a string[N] record field.

  A frozen string is a BUFFER, not a value: an 8-byte length prefix (low word
  the length, high word zero) followed by the characters, laid out inline in
  the frame, in BSS, or inside a record. That is what makes assignment to one a
  length-clamped COPY rather than a store, and it is why every case below is a
  different mechanism wearing the same syntax:

    s := 'literal'      copy from a frozen blob in Data[]
    s := c              a Char is one character, not a string — the prefix has
                        to be MADE, not copied
    t := s              frozen to frozen, and t may be shorter
    r.nm := 'x'         the destination is an address, not a symbol, so the
                        capacity comes from the IR node rather than the symbol

  Truncation is deliberate in three of the cases and is the property most
  likely to be silently dropped: a copy that ignores the capacity writes past
  the variable into whatever the frame put next to it, which is a memory bug
  that prints the right answer until something else moves. Each truncating case
  below is paired with its Length, so a copy that wrote the untruncated length
  word fails on the number even when the characters happen to look right. }

type
  TRec = record
    tag: Integer;
    nm: string[8];
    tail: Integer;      { a NEIGHBOUR: an overrunning copy into nm lands here }
  end;

var
  s: string[15];
  t: string[5];
  c: Char;
  r: TRec;
  i: Integer;

{ A frozen string as a PARAMETER. The slot holds the address of a buffer, on
  every target — abi.inc calls that the SLOT-HOLDS question and answers it for
  frozen strings, open arrays, variants and var/out alike. So the two shapes
  below are the same convention and differ only in who owns the buffer:

    const  the caller's own, passed straight through
    value  a hidden temp the IR fills with an ordinary frozen-string
           assignment, so writing to it must NOT reach the caller's variable —
           bug-a-set-and-shortstring-value-params-alias-the-caller is what the
           other arrangement looks like, and Mut below is the check for it

  A frozen string as a RESULT is deliberately absent: that is the caller-owned
  hidden destination (abi.inc RetViaHiddenDest), shared with records, sets,
  variants and promotable ints, and this target refuses it by name. }
procedure ShowConst(const x: ShortString);
begin
  writeln('c:', x, '|', Length(x));
end;

procedure Mut(x: ShortString);
begin
  x[1] := '!';
  writeln('v:', x, '|', Length(x));
end;

begin
  s := 'hello';
  writeln(s, '|', Length(s));

  t := 'truncate me';                 { 11 chars into a string[5] }
  writeln(t, '|', Length(t));

  c := 'Z';                           { Char source: the prefix is made }
  s := c;
  writeln(s, '|', Length(s));

  t := s;                             { frozen -> frozen }
  writeln(t, '|', Length(t));

  s := 'abcdefghijklmnop';            { 16 into a string[15] }
  writeln(s, '|', Length(s));

  s := '';                            { empty: length word must be zeroed }
  writeln('[', s, ']|', Length(s));

  r.tag := 3;
  r.tail := 77;
  r.nm := 'field name';               { 10 into a string[8], through an ADDRESS }
  writeln(r.nm, '|', Length(r.nm), '|', r.tag, '|', r.tail);

  s := 'wxyz';                        { indexing reads chars at +8 }
  for i := 1 to Length(s) do write(s[i], '.');
  writeln;

  s := 'abcdef';
  ShowConst(s);
  ShowConst('a literal');
  Mut(s);
  writeln('after :', s);      { Mut wrote through a COPY: s is untouched }
end.
