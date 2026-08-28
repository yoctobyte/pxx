program ManagedSlice;
{ Managed (reference-counted) string ASSIGNMENT — the publish half of Phase 8.

  Every line here exists because the wrong lowering of it is a valid module
  that prints something. A managed string's slot is pointer-sized, so a plain
  store compiles: `s := 'lit'` becomes the address of the literal's frozen
  [len][chars] blob written where a heap handle belongs, and every later read
  is off by the 8-byte prefix. That is the failure this slice is aimed at, and
  the reason each source shape appears separately: literal, Char, frozen,
  another managed string, self, a function result, a record field, a var
  parameter, and the empty string, which is the nil handle.

  Concatenation and comparison are NOT here — they are RTL calls this target
  does not make yet and are refused by name (check_managed.sh asserts that). }

type
  TRec = record
    name: string;
    tail: Integer;
  end;

var
  s, t: string;
  c: Char;
  fz: string[15];
  r: TRec;
  i: Integer;

function Make(n: Integer): string;
begin
  if n = 1 then Make := 'one' else Make := 'many';
end;

procedure Fill(var d: string);
begin
  d := 'byref';
end;

procedure Local;
var u: string;
begin
  u := 'local';
  writeln(u, '|', Length(u));
end;

begin
  s := 'literal';
  writeln(s, '|', Length(s));

  c := 'Q';
  s := c;
  writeln(s, '|', Length(s));

  fz := 'frozen src';
  s := fz;
  writeln(s, '|', Length(s));

  t := 'other';
  s := t;
  writeln(s, '|', t, '|', Length(s));

  { Aliasing, and it only bites when s is the SOLE owner: after `s := t` the
    block has two references, so the wrong order (release, then retain) would
    take it to 1 and back to 2 and look correct. Dropping t first makes s the
    only holder, so release-first frees the block that retain-then-read is
    about to touch. Verified by swapping the two steps: this line prints
    garbage and the diff fails. }
  t := '';
  s := 'sole owner';
  s := s;
  { The reuse is what makes the aliasing case OBSERVABLE, and without it the
    test cannot fail. Under the wrong order (release, then retain) s's block —
    it is the sole reference now that t is empty — goes on the free list, and
    the next same-sized allocation pops it and overwrites the characters s is
    still pointing at. `ten charac` is ten bytes, exactly `sole owner`'s
    length, so it lands in the same size bin. Verified by swapping the two
    steps in WasmEmitManagedStore: this prints `ten charac|10` and the diff
    fails. Without this line the wrong order still prints the right answer,
    because a freed block keeps its bytes until something reuses it. }
  t := 'ten charac';
  writeln(s, '|', Length(s), '|', t);

  { A function result arrives already owned — retaining it again leaks, and
    NOT retaining a plain variable double-frees. Both shapes, adjacent. }
  s := Make(1);
  writeln(s);
  s := Make(2);
  writeln(s);

  r.name := 'field';
  r.tail := 77;
  writeln(r.name, '|', r.tail, '|', Length(r.name));

  Fill(s);
  writeln(s, '|', Length(s));

  { Reassignment in a loop: the release of the previous value runs three
    times, and a missing one is invisible here on purpose — the leak is the
    subject of the cleanup half, not of this diff. }
  for i := 1 to 3 do
  begin
    s := Make(i);
    writeln(i, ':', s);
  end;

  { The empty string is the NIL handle, and PXXStrDecRef must tolerate it. }
  s := '';
  writeln('[', s, ']', Length(s));

  Local;
  writeln('end');
end.
