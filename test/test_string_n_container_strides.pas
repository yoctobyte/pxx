program test_string_n_container_strides;
{ A `string[N]` ELEMENT must keep its declared capacity through every container
  shape, and the assertion has to be the STRIDE, not the value.

  WHY VALUES CANNOT SEE THIS. Each of the three bugs below made a write and the
  matching read agree with each other on a wrong stride, so `a[i] := s;
  WriteLn(a[i])` round-trips perfectly while the neighbouring element, or the
  memory after the array, is being destroyed. Every shape here was GREEN on
  values for as long as it was broken. The rows that move are the stride rows
  and the guard.

  AND THE STRIDE MUST BE MEASURED, NOT WRITTEN DOWN. `SizeOf(TS)` is 18 today
  and becomes 11 when the byte-length prefix lands
  (feature-p-implement-the-real-tyshortstring-byte-prefix-layout), so a test
  asserting 18 would go red on a correct change and be "fixed" by pinning the
  old layout. Every row below compares one measured stride against another.

  THE THREE SHAPES, and each had a DIFFERENT cause -- which is the reason they
  are one test: they looked like one bug and were three.

  1. OPEN-ARRAY PARAMETER. The caller copies a static array into a `[len:8][data]`
     temp; StaticArraySourceInfo sized the element with TypeStorageSize, which
     takes only a KIND, so `array[0..3] of string[10]` copied 4*8 = 32 bytes of a
     72-byte array. Elements past the truncation read EMPTY, not corrupt.

  2. A PARAMETER FOLLOWING IT. AllocParam read LastTypeStrCap -- a parse-window
     return channel -- from the ALLOCATION loop, which runs after every
     parameter's type has been parsed. So the capacity a `string[N]` parameter
     got was the LAST parameter's. `P(var a: array of string[10])` was correct
     and `P(var a: array of string[10]; t: LongInt)` strode 263 (DEFAULT_STR_CAP
     + 8, the permissive default). THE FOLLOWING PARAMETER'S TYPE DECIDED THE
     PRECEDING ONE'S LAYOUT, which is why row `openp20` uses a DIFFERENT capacity
     after the array: with string[10] after it the bug is invisible, because the
     wrong answer and the right one coincide.

  3. NESTED DYNAMIC ARRAY. DynElemSize asked TypeSlotSize at depth 1: 8 bytes for
     an 18-byte element, so the inner dimension of `array of array of string[10]`
     strode 8 and every write but the last landed on its neighbour. The 1-D
     spelling was correct throughout -- its base is an AN_IDENT and takes a
     different arm -- so two spellings of one construct disagreed, which is the
     shape devdocs/dev/normalise-dont-special-case.md is about.

  MEASURED POSITIVE CONTROL, and it is reported honestly rather than claimed.
  Built with the PINNED compiler (which predates all three fixes) the rows come
  out:

      openp1 0   openp2 0   openp20 0   openvals 1
      dyn1d  1   dyn2d  0   dyn2dvals 0   guard   1

  So FIVE of eight rows move, and the three that do NOT are worth naming.
  `openvals` inspects the caller's array, which was never wrong -- it is here to
  show that the obvious assertion is the one that cannot fail. `dyn1d` is the
  spelling that was always correct and is the reference the `dyn2d` row is
  compared against; a green `dyn1d` beside a red `dyn2d` is the finding.
  `guard` does not fire for THESE three bugs, because all three read short or
  strode inside a copy rather than writing past `g` -- it fires for the
  record-field shape this ticket already fixed, where `@inner[1]` landed 224
  bytes beyond a 40-byte record. It is kept because a capacity that goes missing
  in a NEW shape is as likely to overrun as to under-read, and the guard is the
  only row that could see that.

  bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes }
type
  TS = string[10];
  TS20 = string[20];
var
  g: array[0..3] of TS;
  guard: array[0..15] of LongInt;
  d1: array of TS;
  m: array of array of TS;
  i, j, callee1, callee2, callee3, base1D, base2D: Integer;
  ok: Boolean;

function StrideOf(var a: array of TS): Integer;
begin StrideOf := Integer(PtrUInt(@a[1]) - PtrUInt(@a[0])); end;

{ the sole-parameter spelling -- correct even while the two below were not }
function S1(var a: array of TS): Integer;
begin S1 := StrideOf(a); end;

{ a parameter FOLLOWS: shape 2's discriminator }
function S2(var a: array of TS; t: LongInt): Integer;
begin S2 := StrideOf(a) + 0 * t; end;

{ ...and one whose capacity DIFFERS, so a wrong answer cannot coincide }
function S3(var a: array of TS; t: TS20): Integer;
begin S3 := StrideOf(a) + 0 * Length(t); end;

begin
  for i := 0 to 15 do guard[i] := 1000 + i;
  for i := 0 to 3 do g[i] := 'e' + Chr(48 + i);

  { The reference stride, measured in the caller where it was never wrong. }
  base1D := Integer(PtrUInt(@g[1]) - PtrUInt(@g[0]));

  callee1 := S1(g);
  callee2 := S2(g, 7);
  callee3 := S3(g, 'twenty');
  WriteLn('openp1     ', Ord(callee1 = base1D));
  WriteLn('openp2     ', Ord(callee2 = base1D));
  WriteLn('openp20    ', Ord(callee3 = base1D));

  { the element the truncated copy could not reach }
  ok := True;
  for i := 0 to 3 do
    if g[i] <> 'e' + Chr(48 + i) then ok := False;
  WriteLn('openvals   ', Ord(ok));

  { A 1-D dyn array and the INNER dimension of a 2-D one describe the same
    element, so their strides must be equal. Neither number is written down. }
  SetLength(d1, 4);
  SetLength(m, 3);
  for i := 0 to 2 do SetLength(m[i], 3);
  base2D := Integer(PtrUInt(@d1[1]) - PtrUInt(@d1[0]));
  WriteLn('dyn1d      ', Ord(base2D = base1D));
  WriteLn('dyn2d      ', Ord(Integer(PtrUInt(@m[0][1]) - PtrUInt(@m[0][0])) = base2D));

  for i := 0 to 2 do
    for j := 0 to 2 do m[i][j] := 'r' + Chr(48 + i) + 'c' + Chr(48 + j);
  ok := True;
  for i := 0 to 2 do
    for j := 0 to 2 do
      if m[i][j] <> 'r' + Chr(48 + i) + 'c' + Chr(48 + j) then ok := False;
  WriteLn('dyn2dvals  ', Ord(ok));

  { THE GUARD IS THE ROW A VALUE TEST CANNOT REPLACE. A stride wider than the
    element walks off the end of `g` and writes into whatever follows it; the
    array's own values stay self-consistent while it happens. }
  ok := True;
  for i := 0 to 15 do
    if guard[i] <> 1000 + i then ok := False;
  WriteLn('guard      ', Ord(ok));
end.
