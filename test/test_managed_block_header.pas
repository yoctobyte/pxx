program test_managed_block_header;
{ feature-a-managed-block-kind-word — the shared managed-block header
  [kind:8][refcount:8][length:8][data], handle = block+24.

  Pins the three header-relative facts that a layout change can break silently,
  one per consumer of the header. Every check is a VALUE check, because every
  failure mode here is a wrong value or a corrupted neighbour rather than a
  crash at the mistake.

  The string-growth loops are the point of the file, not filler. The in-place
  resize fast path compares the requested size against the ALLOCATOR's capacity
  word, which lives 8 bytes below our block base and therefore MOVED when the
  kind word was added. Get that offset wrong and a grow that should reallocate
  instead writes past the end of its block into the neighbour — which shows up
  as the neighbour's contents changing, not as a fault here. So each loop keeps
  a witness string allocated beside the one being grown and checks it afterwards. }

procedure Fail(const what: AnsiString);
begin
  WriteLn('FAIL ', what);
  Halt(1);
end;

var
  s, witness, t: AnsiString;
  arr: array of Integer;
  strs: array of AnsiString;
  i, n: Integer;

begin
  { --- strings: repeated growth across the in-place/realloc boundary --- }
  witness := 'WITNESS-KEEP-ME';
  s := '';
  for i := 1 to 500 do
    s := s + 'a';
  if Length(s) <> 500 then Fail('grown length');
  if s[1] <> 'a' then Fail('grown first char');
  if s[500] <> 'a' then Fail('grown last char');
  if witness <> 'WITNESS-KEEP-ME' then Fail('neighbour clobbered by string growth');

  { shrink then regrow — exercises the capacity path with a live buffer }
  SetLength(s, 3);
  if Length(s) <> 3 then Fail('shrunk length');
  for i := 1 to 200 do
    s := s + 'b';
  if Length(s) <> 203 then Fail('regrown length');
  if s[1] <> 'a' then Fail('regrown prefix preserved');
  if s[203] <> 'b' then Fail('regrown tail');
  if witness <> 'WITNESS-KEEP-ME' then Fail('neighbour clobbered by regrow');

  { concat allocates a fresh block rather than growing one }
  t := s + witness;
  if Length(t) <> 203 + 15 then Fail('concat length');
  if witness <> 'WITNESS-KEEP-ME' then Fail('concat clobbered its source');

  { empty string is a nil handle — must not be dereferenced as a block }
  s := '';
  if Length(s) <> 0 then Fail('empty length');
  s := s + 'x';
  if Length(s) <> 1 then Fail('grow from empty');

  { --- dynamic arrays: same header, length at [data-8] --- }
  SetLength(arr, 6);
  for i := 0 to 5 do arr[i] := i * 11;
  if Length(arr) <> 6 then Fail('array length');
  if arr[5] <> 55 then Fail('array element');
  SetLength(arr, 40);
  if Length(arr) <> 40 then Fail('array regrown length');
  if arr[5] <> 55 then Fail('array prefix preserved across regrow');
  if arr[39] <> 0 then Fail('array tail zeroed');
  SetLength(arr, 2);
  if Length(arr) <> 2 then Fail('array shrunk length');
  if arr[1] <> 11 then Fail('array prefix preserved across shrink');

  { --- managed elements: a block whose payload is itself refcounted --- }
  SetLength(strs, 25);
  for i := 0 to 24 do
    strs[i] := 'e' + Chr(48 + (i mod 10));
  n := 0;
  for i := 0 to 24 do
    if Length(strs[i]) = 2 then n := n + 1;
  if n <> 25 then Fail('managed element lengths');
  if strs[24] <> 'e4' then Fail('managed element value');
  SetLength(strs, 3);
  if Length(strs) <> 3 then Fail('managed array shrunk');
  if strs[0] <> 'e0' then Fail('managed element survived shrink');
  if witness <> 'WITNESS-KEEP-ME' then Fail('witness survived everything');

  WriteLn('managed block header ok');
end.
