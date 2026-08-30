program BulkCopyTails;
{ The byte tail is where a word loop goes wrong, so every length 0..17 is
  exercised on every path that now calls PXXBlockCopy / PXXMemZero: string
  SetLength (grow and shrink), dyn-array SetLength (grow and shrink), Copy() at
  every offset and count, and the shared-array duplicate. Odd lengths and
  sub-word sizes are the point; 0 is included because an empty copy is the case
  a `while i < n` loop got right for free and a word loop can get wrong.

  Every expectation here is diffed against FPC 3.2.2 rather than asserted from
  first principles. Two of them were wrong before that diff:
    - dyn-array assignment ALIASES in Pascal (it is a reference type with no
      copy-on-write), so a write through the second name is visible through the
      first. An earlier version of this file expected a private copy.
    - and it used `n := min(i,j); for n := 1 to n do`, which pxx miscompiles —
      bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned.
      Distinct loop variables below, deliberately. }
var
  s, t: AnsiString;
  a, b, c: array of LongInt;
  i, j, k, lim: LongInt;
  ok: Boolean;
  bad: LongInt;

function MakeStr(len: LongInt): AnsiString;
var q: LongInt; r: AnsiString;
begin
  r := '';
  for q := 1 to len do r := r + Chr(Ord('a') + (q mod 26));
  MakeStr := r;
end;

begin
  bad := 0;

  { --- string SetLength, every from-length to every to-length --- }
  for i := 0 to 17 do
    for j := 0 to 17 do
    begin
      s := MakeStr(i);
      t := MakeStr(i);
      SetLength(s, j);
      ok := (Length(s) = j);
      lim := i; if j < lim then lim := j;
      for k := 1 to lim do
        if s[k] <> t[k] then ok := False;
      if j > i then
        for k := i + 1 to j do
          if s[k] <> #0 then ok := False;
      if not ok then begin WriteLn('str setlen BAD ', i, '->', j); bad := bad + 1; end;
    end;

  { --- dyn-array SetLength, every pair --- }
  for i := 0 to 17 do
    for j := 0 to 17 do
    begin
      SetLength(a, 0);
      SetLength(a, i);
      for k := 0 to i - 1 do a[k] := k + 1;
      SetLength(a, j);
      ok := (Length(a) = j);
      lim := i; if j < lim then lim := j;
      for k := 0 to lim - 1 do
        if a[k] <> k + 1 then ok := False;
      if j > i then
        for k := i to j - 1 do
          if a[k] <> 0 then ok := False;
      if not ok then begin WriteLn('dyn setlen BAD ', i, '->', j); bad := bad + 1; end;
    end;

  { --- Copy() at every offset and count over a 17-element source --- }
  SetLength(b, 17);
  for k := 0 to 16 do b[k] := 100 + k;
  for i := 0 to 17 do
    for j := 0 to 17 do
    begin
      c := Copy(b, i, j);
      lim := 17 - i; if lim < 0 then lim := 0;
      if j < lim then lim := j;
      ok := (Length(c) = lim);
      if ok then
        for k := 0 to lim - 1 do
          if c[k] <> 100 + i + k then ok := False;
      if not ok then begin WriteLn('copy BAD idx=', i, ' cnt=', j, ' len=', Length(c)); bad := bad + 1; end;
    end;

  { --- a dyn array is a REFERENCE: assignment aliases, Copy does not --- }
  for i := 1 to 17 do
  begin
    SetLength(a, i);
    for k := 0 to i - 1 do a[k] := k + 50;
    b := a;              { aliases }
    c := Copy(a);        { does not }
    b[0] := -1;
    ok := (a[0] = -1) and (b[0] = -1) and (c[0] = 50)
          and (Length(a) = i) and (Length(b) = i) and (Length(c) = i);
    for k := 1 to i - 1 do
      if (a[k] <> k + 50) or (c[k] <> k + 50) then ok := False;
    if not ok then begin WriteLn('alias/copy BAD len=', i); bad := bad + 1; end;
  end;

  { --- string concat at odd lengths, through the same block copy --- }
  for i := 0 to 17 do
  begin
    s := MakeStr(i);
    t := s + s;
    ok := (Length(t) = 2 * i);
    for k := 1 to i do
      if (t[k] <> s[k]) or (t[i + k] <> s[k]) then ok := False;
    if not ok then begin WriteLn('concat BAD len=', i); bad := bad + 1; end;
  end;

  if bad = 0 then WriteLn('BULK COPY TAILS OK') else WriteLn('FAILURES: ', bad);
end.
