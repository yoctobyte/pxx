program test_dynarray_grows_in_place;
{ SetLength on a UNIQUE dynamic array grows the existing block in place when the
  allocator's size word still has room, and the allocation path that does have to
  move takes geometric headroom off the LENGTH so the next grows do not.

  THE LOAD-BEARING ROW IS `reallocations` (row 1) AND IT IS THE POSITIVE
  CONTROL: it counts how many of 4095 one-element grows actually moved the data
  pointer. Before feature-opt-dynarray-grows-in-place it was 4095 -- every
  SetLength allocated, copied and abandoned a block the large free list could
  never hand back, because first-fit needs `size >= request` and a freed 2^k
  block cannot serve 2^(k+1). Measured on the same host, same program: 44.3 s
  and 3.1 GB max RSS became 0.02 s and 392 KB. If someone removes the fast path
  or the headroom, this row goes back to 4095 and fails; the other rows would
  all still pass, which is exactly why it is here.

  Every other row is the other half: the cases where growing in place would be
  WRONG. A shared block (refcount > 1) must still copy, or one view scribbles on
  the other. A shrink must still allocate, because dropping elements is what
  releases the managed ones. And a regrow must zero its new tail -- the capacity
  it grows into is the span PXXAlloc did NOT zero, since the large first-fit
  path hands back an oversized block with its original size word and only
  `size` bytes cleared. }
var
  ok, total: Integer;

procedure Chk(name: AnsiString; cond: Boolean);
begin
  Inc(total);
  if cond then begin Inc(ok); WriteLn('ok   ', name); end
  else WriteLn('FAIL ', name);
end;

type
  TRec = record n: Integer; s: AnsiString; end;
  THolder = record tag: Integer; arr: array of Integer; end;
var
  hold: THolder;
  grid: array of array of Integer;
  a, b: array of Integer;
  ms: array of AnsiString;
  rs: array of TRec;
  nest: array of array of Integer;
  p0, p: PtrUInt;
  i, j, moves: Integer;
  sum: Int64;
begin
  ok := 0; total := 0;

  { 1. the positive control -- 4095 one-element grows, counting real moves }
  SetLength(a, 1);
  a[0] := 1;
  p0 := PtrUInt(@a[0]);
  moves := 0;
  for i := 2 to 4096 do
  begin
    SetLength(a, i);
    a[i - 1] := i;
    p := PtrUInt(@a[0]);
    if p <> p0 then begin Inc(moves); p0 := p; end;
  end;
  Chk('reallocations bounded (grew in place)', (moves >= 1) and (moves <= 40));

  { and the values survived every one of them }
  sum := 0;
  for i := 0 to 4095 do sum := sum + a[i];
  Chk('4096 grows preserve every element', (Length(a) = 4096) and (sum = 8390656));

  { 2. a SHARED block must copy, not grow in place }
  SetLength(b, 3);
  b[0] := 7; b[1] := 8; b[2] := 9;
  a := b;                       { refcount 2 }
  SetLength(b, 6);
  b[3] := 100;
  Chk('shared block copies on grow', (Length(a) = 3) and (Length(b) = 6)
      and (a[0] = 7) and (a[2] = 9) and (b[3] = 100));

  { 3. shrink still drops, and the regrown tail is zero }
  SetLength(a, 0);
  SetLength(a, 8);
  for i := 0 to 7 do a[i] := i + 1;
  SetLength(a, 3);
  Chk('shrink truncates', (Length(a) = 3) and (a[2] = 3));
  SetLength(a, 6);
  Chk('regrown tail is zeroed', (Length(a) = 6) and (a[2] = 3)
      and (a[3] = 0) and (a[4] = 0) and (a[5] = 0));

  { 4. managed elements survive in-place growth and the new tail is empty }
  for i := 0 to 19 do
  begin
    SetLength(ms, i + 1);
    ms[i] := 'e' + Chr(Ord('0') + (i mod 10));
  end;
  Chk('managed elements survive growth',
      (Length(ms) = 20) and (ms[0] = 'e0') and (ms[19] = 'e9'));
  SetLength(ms, 4);
  SetLength(ms, 7);
  Chk('managed regrown tail is empty',
      (ms[3] = 'e3') and (ms[4] = '') and (ms[6] = ''));

  { 5. records with a managed field }
  for i := 0 to 19 do
  begin
    SetLength(rs, i + 1);
    rs[i].n := i;
    rs[i].s := 'r' + Chr(Ord('0') + (i mod 10));
  end;
  Chk('record elements survive growth',
      (Length(rs) = 20) and (rs[0].s = 'r0') and (rs[19].n = 19) and (rs[19].s = 'r9'));

  { 6. nested: the outer array's elements are handles }
  for i := 0 to 9 do
  begin
    SetLength(nest, i + 1);
    SetLength(nest[i], 3);
    for j := 0 to 2 do nest[i][j] := i * 10 + j;
  end;
  sum := 0;
  for i := 0 to Length(nest) - 1 do
    for j := 0 to Length(nest[i]) - 1 do sum := sum + nest[i][j];
  Chk('nested arrays survive outer growth', (Length(nest) = 10) and (sum = 1380));

  { 7. the NESTED/FIELD lowering is a second emit site, and it has its own
    positive control: a record field and an array element are reached through
    IR_SETLEN_DYN, which the symbol-target arm never sees. Both read 2047 on the
    pre-fix compiler. }
  SetLength(hold.arr, 1);
  hold.arr[0] := 1;
  p0 := PtrUInt(@hold.arr[0]);
  moves := 0;
  for i := 2 to 2048 do
  begin
    SetLength(hold.arr, i);
    hold.arr[i - 1] := i;
    p := PtrUInt(@hold.arr[0]);
    if p <> p0 then begin Inc(moves); p0 := p; end;
  end;
  sum := 0;
  for i := 0 to 2047 do sum := sum + hold.arr[i];
  Chk('record field grows in place',
      (moves >= 1) and (moves <= 40) and (Length(hold.arr) = 2048) and (sum = 2098176));

  SetLength(grid, 2);
  SetLength(grid[1], 1);
  grid[1][0] := 5;
  p0 := PtrUInt(@grid[1][0]);
  moves := 0;
  for i := 2 to 2048 do
  begin
    SetLength(grid[1], i);
    grid[1][i - 1] := i;
    p := PtrUInt(@grid[1][0]);
    if p <> p0 then begin Inc(moves); p0 := p; end;
  end;
  Chk('array element grows in place',
      (moves >= 1) and (moves <= 40) and (Length(grid[1]) = 2048)
      and (grid[1][0] = 5) and (grid[1][2047] = 2048) and (Length(grid[0]) = 0));

  { 8. a one-shot SetLength from nil takes no headroom it then has to keep }
  a := nil;
  SetLength(a, 1000);
  Chk('one-shot sizing from nil', (Length(a) = 1000) and (a[999] = 0));

  WriteLn('total ok ', ok, ' / ', total);
end.
