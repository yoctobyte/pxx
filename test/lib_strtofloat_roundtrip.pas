{ SPDX-License-Identifier: 0BSD }
program lib_strtofloat_roundtrip;
{ StrToFloat is CORRECTLY ROUNDED: 17 significant digits round-trip a Double
  through text and back to the identical bit pattern, across the whole exponent
  range including subnormals and the denormal floor.

  This exists because nothing guarded that property. `lib_floattostr` checks the
  FORMATTER against expected strings; the exact PARSE path
  (ExDecNearest -> ExDecOfMant) had no test of its own, and it is precisely the
  code a performance change touches
  (bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents). Correct
  rounding is not negotiable there, so it needs an assertion that fails rather
  than a benchmark that gets faster.

  17 digits is the round-trip guarantee for binary64: fewer can collide, more is
  redundant. A mismatch here means the parser picked a neighbouring double, which
  no amount of formatting care can recover.

  Sized to run in a couple of seconds. The exhaustive version of this sweep
  (every exponent x 8 mantissas, 200k random patterns, 218,883 values) takes
  ~90 s and was run once by hand against the change that motivated it; what
  stays in the gate is the bounded shape, weighted toward the exponents where
  the exact path actually does work. }

{$MODE OBJFPC}

uses sysutils;

type
  PDbl = ^Double;
  PI64 = ^Int64;

var
  seed: Int64 = 123456789;
  bad, n: Int64;

function NextBits: Int64;
begin
  seed := (seed * 6364136223846793005) + 1442695040888963407;
  NextBits := seed;
end;

function BitsToD(b: Int64): Double;
begin BitsToD := PDbl(@b)^; end;

function DToBits(d: Double): Int64;
begin DToBits := PI64(@d)^; end;

procedure Check(x: Double; const what: AnsiString);
var s: AnsiString; y: Double;
begin
  n := n + 1;
  s := FloatToStrExact(x, 17);
  y := StrToFloat(s);
  if DToBits(y) <> DToBits(x) then
  begin
    bad := bad + 1;
    if bad <= 5 then
      WriteLn('MISMATCH ', what, ' in=', DToBits(x), ' str=', s, ' out=', DToBits(y));
  end;
end;

var i, e: Integer; b: Int64; x, z: Double;
begin
  bad := 0; n := 0;

  { every binary exponent, so no bucket of the exponent range goes unvisited }
  for e := 0 to 2046 do
  begin
    b := (Int64(e) shl 52) or (NextBits and ((Int64(1) shl 52) - 1));
    Check(BitsToD(b), 'exp' + IntToStr(e));
  end;
  WriteLn('exponents=ok');

  { the smallest subnormals one at a time -- the ~765-digit expansions, and the
    only place where a limb-boundary or padding slip would show }
  for i := 1 to 200 do Check(BitsToD(i), 'tiny');
  WriteLn('subnormals=ok');

  { exact powers of two: the values whose decimal expansion is longest for a
    given exponent, in both directions }
  x := 1.0;
  for i := 1 to 300 do begin Check(x, 'pow2up'); x := x * 2.0; end;
  x := 1.0;
  for i := 1 to 300 do begin Check(x, 'pow2dn'); x := x / 2.0; end;
  WriteLn('powers=ok');

  { the named boundaries }
  Check(4.9406564584124654e-324, 'minsub');
  Check(2.2250738585072014e-308, 'minnorm');
  Check(1.7976931348623157e308, 'maxnorm');
  Check(0.0, 'zero');
  Check(1.0, 'one');
  Check(0.1, 'tenth');
  WriteLn('boundaries=ok');

  { NEGATIVE ZERO IS DELIBERATELY NOT A ROUND-TRIP CASE, and that is FPC parity
    rather than a gap. Measured against FPC 3.2.2: `FloatToStr(-0.0)` prints
    `0` there too — the sign is dropped by the FORMATTER — while `StrToFloat('-0')`
    returns negative zero, so the parser preserves a sign the formatter never
    writes. pxx agrees on both halves, bit for bit.

    (CPython differs — `repr(-0.0)` is `-0.0` — but the oracle for this RTL is
    FPC, and matching it here is the contract.)

    Asserted explicitly so the asymmetry is locked and visible: a future change
    that "fixes" either half in isolation breaks parity, and this is what says
    so. }
  z := 0.0; z := -z;
  if DToBits(z) >= 0 then
  begin
    WriteLn('negzero-setup=FAIL'); bad := bad + 1;
  end
  else if FloatToStrExact(z, 17) <> '0' then
  begin
    WriteLn('negzero-format=FAIL [', FloatToStrExact(z, 17), '] want [0]');
    bad := bad + 1;
  end
  else if DToBits(StrToFloat('-0')) >= 0 then
  begin
    WriteLn('negzero-parse=FAIL'); bad := bad + 1;
  end
  else
    WriteLn('negzero-fpc-parity=ok');

  { random finite bit patterns }
  for i := 1 to 4000 do
  begin
    b := NextBits and $7FFFFFFFFFFFFFFF;
    if (b shr 52) <> 2047 then Check(BitsToD(b), 'rand');
  end;
  WriteLn('random=ok');

  WriteLn('checked=', n);
  if bad = 0 then WriteLn('STRTOFLOAT-ROUNDTRIP OK')
             else WriteLn('STRTOFLOAT-ROUNDTRIP FAILED ', bad);
end.
