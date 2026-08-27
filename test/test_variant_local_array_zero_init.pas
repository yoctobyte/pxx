{ A LOCAL `array[0..N] of Variant` was zero-initialised for ONE ELEMENT only.

    procedure P;
    var av: array[0..3] of Variant;
    begin
      av[3] := Null;     { releases the "old value" -- which is stack junk }
    end;

  ManagedLocalZeroBytes (pasparser_expr.inc) is the one table that answers "how
  many bytes must this managed local start zeroed". Its AnsiString arm asks
  IsArray and multiplies by ArrLen; its VARIANT arm did not, and returned
  TypeSize(tyVariant) -- 16 bytes -- for an array of any length. So av[0]
  started empty and av[1..] held whatever the frame happened to carry.

  A Variant's first word is its TAG, and every assignment to one RELEASES the
  old contents first. When the stale tag under av[1..] read as a kind the
  release path recognises, that first store decremented a refcount through a
  payload the slot never owned -- a live block belonging to something else.

  MEASURED, in pylib's own PyBoundPairCallKwBody, whose `av: array[0..3] of
  Variant` is exactly this shape: `for i := nPos to 3 do av[i] := pynone` ran
  `decq -0x10(%rax)` with rax 40 bytes inside an unrelated bound-pair record,
  taking that record's Sig field from 0x5443A1 to 0x5443A0. The dispatcher then
  read the signature ONE BYTE EARLY, so a two-parameter def's reqN (2) came
  back as 512, and a legal `f(a, b)` through a callable value was refused as
  "missing 510 required positional argument(s)".

  WHAT MADE THIS HARD TO SEE: it is invisible on a clean stack, so it appears
  and disappears when an unrelated routine changes the frame in front of it.
  It surfaced as a NilPy test going red with no NilPy change behind it, and
  vanished under -dPXX_HEAP_DEBUG, under -dPXX_OBJTRACE, and on every attempt
  to instrument it -- each of which shifts the layout. Same shape and the same
  red herring as bug-a-a-local-array-of-interfaces-is-not-zero-initialised,
  which is the SAME arm-shaped hole one type over.

  So this test dirties the stack ITSELF, with a routine that leaves a
  recognisable pattern at the depth the next call reuses. That makes the
  failure deterministic rather than a lottery.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  regression-test-nilpy-test-nilpy-star-operand-in-a-variant }
program test_variant_local_array_zero_init;
{$mode objfpc}{$H+}

var
  ok, total: Integer;

procedure Check(const what: string; got, want: Int64);
begin
  Inc(total);
  if got = want then
  begin
    Inc(ok);
    WriteLn('ok   ', what);
  end
  else
    WriteLn('FAIL ', what, ' got=', got, ' want=', want);
end;

{ Leave a recognisable pattern where the next call's frame will land. The
  values are chosen to look like LIVE managed tags rather than zero -- that is
  the whole hazard, and a pattern of zeroes would test nothing. }
procedure DirtyFrame;
var junk: array[0..47] of Int64; i: Integer;
begin
  for i := 0 to 47 do junk[i] := 1 + (i mod 5);
  if junk[0] = -12345 then WriteLn('unreachable');
end;

{ Read the raw first word of each slot. A zero-initialised Variant is 16 zero
  bytes under both FPC and pxx, so the tag word is the portable observable. }
function SlotTag(p: Pointer): Int64;
begin
  SlotTag := PInt64(p)^;
end;

procedure ProbeFour;
var av: array[0..3] of Variant;
begin
  Check('av[0] starts empty', SlotTag(@av[0]), 0);
  Check('av[1] starts empty', SlotTag(@av[1]), 0);
  Check('av[2] starts empty', SlotTag(@av[2]), 0);
  Check('av[3] starts empty', SlotTag(@av[3]), 0);
end;

{ A longer array: the arm returned a FIXED 16 bytes, so the hole grows with the
  declared length and one length proves nothing about another. }
procedure ProbeEight;
var av: array[0..7] of Variant; i, bad: Integer;
begin
  bad := 0;
  for i := 0 to 7 do
    if SlotTag(@av[i]) <> 0 then Inc(bad);
  Check('all 8 slots start empty', bad, 0);
end;

{ The store side: assigning into every slot must not disturb a live managed
  value the routine did not touch. `s` is an ordinary refcounted string; a
  release through a stale payload lands on whatever the allocator handed out
  most recently, which is exactly what this shape produced in pylib. }
procedure StoreIntoAll;
var av: array[0..3] of Variant; s: AnsiString; i: Integer;
begin
  s := 'the string that must survive';
  for i := 0 to 3 do av[i] := i * 10;
  Check('stores land',        av[3], 30);
  Check('live string intact', Length(s), 28);
end;

{ A slot never written on the taken path is still RELEASED at scope exit, so
  the init half matters even when the store half never runs. }
procedure PartiallyWritten(n: Integer);
var av: array[0..3] of Variant;
begin
  if n > 0 then av[0] := n;
  Check('partial write survives scope exit', av[0], n);
end;

begin
  ok := 0; total := 0;
  DirtyFrame; ProbeFour;
  DirtyFrame; ProbeEight;
  DirtyFrame; StoreIntoAll;
  DirtyFrame; PartiallyWritten(7);
  WriteLn('total ok ', ok, ' / ', total);
end.
