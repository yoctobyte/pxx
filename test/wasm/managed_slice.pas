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

  { Aliasing: release-before-retain would free the block this reads. }
  s := s;
  writeln(s, '|', Length(s));

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
