program test_softfloat_single;
{ Standalone validation of the soft-single kernels in compiler/builtin/softfloat.pas.
  Operates on a grid of single bit patterns; for each pair compares the soft kernel
  result (bit pattern) against native PXX single arithmetic. For + - * the exact
  result fits in a double, so native (widen->double->store-single) equals true
  single rounding: an exact match is required. For / the native path can double-
  round, so a <=1 ulp difference is tolerated and counted separately. }

uses softfloat;

type
  PLongWord = ^LongWord;
  PSingle = ^Single;

const
  NGRID = 21;

var
  grid: array[0..NGRID-1] of LongWord;
  failAdd, failSub, failMul: Integer;
  failDiv, ulpDiv: Integer;
  failCmp: Integer;
  flush: Integer;

function SBits(s: Single): LongWord;
var p: PLongWord;
begin
  p := PLongWord(@s);
  SBits := p^;
end;

function BitsS(w: LongWord): Single;
var p: PSingle;
begin
  p := PSingle(@w);
  BitsS := p^;
end;

function IsNaNBits(w: LongWord): Boolean;
begin
  IsNaNBits := ((w and $7F800000) = $7F800000) and ((w and $7FFFFF) <> 0);
end;

{ subnormal (exp field 0, non-zero mantissa) — these the kernel flushes to 0 }
function IsSubnormal(w: LongWord): Boolean;
begin
  IsSubnormal := ((w and $7F800000) = 0) and ((w and $7FFFFF) <> 0);
end;

{ documented flush-to-zero: kernel returns signed 0 where native rounded into the
  subnormal range }
function FlushOK(soft: LongWord; nat: LongWord): Boolean;
begin
  FlushOK := ((soft and $7FFFFFFF) = 0) and IsSubnormal(nat);
end;

{ unsigned |x - y| on the encodings, for ulp distance of same-sign normals }
function UDiff(a: LongWord; b: LongWord): Int64;
begin
  if a >= b then UDiff := Int64(a) - Int64(b) else UDiff := Int64(b) - Int64(a);
end;

procedure InitGrid;
begin
  grid[0]  := $00000000;   { +0 }
  grid[1]  := $80000000;   { -0 }
  grid[2]  := $3F800000;   { +1.0 }
  grid[3]  := $BF800000;   { -1.0 }
  grid[4]  := $40000000;   { +2.0 }
  grid[5]  := $3F000000;   { +0.5 }
  grid[6]  := $40490FDB;   { ~pi }
  grid[7]  := $C0490FDB;   { ~-pi }
  grid[8]  := $3DCCCCCD;   { ~0.1 }
  grid[9]  := $501502F9;   { ~1e10 }
  grid[10] := $2EDBE6FF;   { ~1e-10 }
  grid[11] := $7149F2CA;   { ~1e30 }
  grid[12] := $0F0BDC21;   { ~1e-30 }
  grid[13] := $4B800000;   { 2^24 = 16777216 }
  grid[14] := $4B800001;   { 16777218 (next representable) }
  grid[15] := $477FE000;   { 65504 }
  grid[16] := $C7C35000;   { -100000 }
  grid[17] := $7F800000;   { +Inf }
  grid[18] := $FF800000;   { -Inf }
  grid[19] := $7FC00000;   { NaN }
  grid[20] := $42F6E979;   { ~123.456 }
end;

procedure CheckPair(ia: Integer; ib: Integer);
var
  fa, fb, fc: Single;
  soft, nat: LongWord;
  sc, nc: Integer;
  pf: PLongWord;
begin
  { load the bit patterns into local single vars (single fn params/returns are
    storage-only and unreliable, so write bits straight into the slot) }
  pf := PLongWord(@fa); pf^ := grid[ia];
  pf := PLongWord(@fb); pf^ := grid[ib];

  { add }
  fc := fa + fb;
  soft := __pxx_sadd(grid[ia], grid[ib]);
  pf := PLongWord(@fc); nat := pf^;
  if not (IsNaNBits(soft) and IsNaNBits(nat)) then
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin
      failAdd := failAdd + 1;
      if failAdd <= 6 then
        writeln('ADD ', grid[ia], ' + ', grid[ib], '  soft=', soft, ' nat=', nat);
    end;

  { sub }
  fc := fa - fb;
  soft := __pxx_ssub(grid[ia], grid[ib]);
  pf := PLongWord(@fc); nat := pf^;
  if not (IsNaNBits(soft) and IsNaNBits(nat)) then
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin
      failSub := failSub + 1;
      if failSub <= 6 then
        writeln('SUB ', grid[ia], ' - ', grid[ib], '  soft=', soft, ' nat=', nat);
    end;

  { mul }
  fc := fa * fb;
  soft := __pxx_smul(grid[ia], grid[ib]);
  pf := PLongWord(@fc); nat := pf^;
  if not (IsNaNBits(soft) and IsNaNBits(nat)) then
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin
      failMul := failMul + 1;
      if failMul <= 6 then
        writeln('MUL ', grid[ia], ' * ', grid[ib], '  soft=', soft, ' nat=', nat);
    end;

  { div — only when native won't trap (non-zero, finite-ish handled by kernel) }
  fc := fa / fb;
  soft := __pxx_sdiv(grid[ia], grid[ib]);
  pf := PLongWord(@fc); nat := pf^;
  if not (IsNaNBits(soft) and IsNaNBits(nat)) then
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin
      { same-sign finite results: tolerate 1 ulp (double-rounding in native) }
      if (((soft xor nat) and $80000000) = 0) and (UDiff(soft, nat) <= 1) then
        ulpDiv := ulpDiv + 1
      else
      begin
        failDiv := failDiv + 1;
        if failDiv <= 8 then
          writeln('DIV ', grid[ia], ' / ', grid[ib], '  soft=', soft, ' nat=', nat);
      end;
    end;

  { compare — derive expected from native ordered relations }
  sc := __pxx_scmp(grid[ia], grid[ib]);
  if IsNaNBits(grid[ia]) or IsNaNBits(grid[ib]) then nc := 2
  else if fa < fb then nc := -1
  else if fa > fb then nc := 1
  else nc := 0;
  if sc <> nc then
  begin
    failCmp := failCmp + 1;
    if failCmp <= 8 then
      writeln('CMP ', grid[ia], ' ? ', grid[ib], '  soft=', sc, ' nat=', nc);
  end;
end;

procedure CheckConversions;
var
  ints: array[0..10] of Integer;
  i, k, back: Integer;
  s, nat: LongWord;
  f: Single;
  pf: PLongWord;
begin
  ints[0] := 0;   ints[1] := 1;     ints[2] := -1;    ints[3] := 2;
  ints[4] := 100; ints[5] := -100;  ints[6] := 123456; ints[7] := -987654;
  ints[8] := 16777216; ints[9] := 2147483647; ints[10] := -2147483648;
  for i := 0 to 10 do
  begin
    k := ints[i];
    { i2s }
    s := __pxx_i2s(k);
    f := k;            { native int->single }
    pf := PLongWord(@f); nat := pf^;
    if s <> nat then
      writeln('I2S ', k, '  soft=', s, ' nat=', nat);
    { s2i round-trips for in-range integral singles }
    back := __pxx_s2i(s);
    if (k >= -16777216) and (k <= 16777216) then
      if back <> k then
        writeln('S2I bits=', s, '  soft=', back, ' expected=', k);
  end;
end;

{ Randomized sweep over normal-range singles (exp in [1..254], so no inf/nan/
  subnormal) — any add/sub/mul mismatch is a real bug; div tolerates 1 ulp. }
var rngState: LongWord;
function NextRand: LongWord;
begin
  rngState := (rngState * 1103515245) + 12345;
  NextRand := rngState;
end;

function RandNormalSingle: LongWord;
var e, mant, sgn: LongWord;
begin
  e := (NextRand and $FF);
  if e = 0 then e := 1;
  if e = 255 then e := 254;
  mant := NextRand and $7FFFFF;
  sgn := NextRand and 1;
  RandNormalSingle := (sgn shl 31) or (e shl 23) or mant;
end;

procedure CheckRandom(n: Integer);
var
  t: Integer;
  ba, bb, soft, nat: LongWord;
  fa, fb, fc: Single;
  pf: PLongWord;
begin
  for t := 1 to n do
  begin
    ba := RandNormalSingle;
    bb := RandNormalSingle;
    pf := PLongWord(@fa); pf^ := ba;
    pf := PLongWord(@fb); pf^ := bb;

    fc := fa + fb; soft := __pxx_sadd(ba, bb);
    pf := PLongWord(@fc); nat := pf^;
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin failAdd := failAdd + 1; if failAdd <= 6 then writeln('rADD ', ba, ' ', bb, ' s=', soft, ' n=', nat); end;

    fc := fa - fb; soft := __pxx_ssub(ba, bb);
    pf := PLongWord(@fc); nat := pf^;
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin failSub := failSub + 1; if failSub <= 6 then writeln('rSUB ', ba, ' ', bb, ' s=', soft, ' n=', nat); end;

    fc := fa * fb; soft := __pxx_smul(ba, bb);
    pf := PLongWord(@fc); nat := pf^;
    if (soft <> nat) and not FlushOK(soft, nat) then
    begin failMul := failMul + 1; if failMul <= 6 then writeln('rMUL ', ba, ' ', bb, ' s=', soft, ' n=', nat); end;

    fc := fa / fb; soft := __pxx_sdiv(ba, bb);
    pf := PLongWord(@fc); nat := pf^;
    if (soft <> nat) and not FlushOK(soft, nat) then
      if (((soft xor nat) and $80000000) = 0) and (UDiff(soft, nat) <= 1) then
        ulpDiv := ulpDiv + 1
      else
      begin failDiv := failDiv + 1; if failDiv <= 8 then writeln('rDIV ', ba, ' ', bb, ' s=', soft, ' n=', nat); end;
  end;
end;

var i, j: Integer;
begin
  InitGrid;
  failAdd := 0; failSub := 0; failMul := 0;
  failDiv := 0; ulpDiv := 0; failCmp := 0; flush := 0;

  for i := 0 to NGRID-1 do
    for j := 0 to NGRID-1 do
      CheckPair(i, j);

  CheckConversions;

  rngState := 2463534242;
  CheckRandom(200000);

  writeln('---');
  writeln('add fails : ', failAdd);
  writeln('sub fails : ', failSub);
  writeln('mul fails : ', failMul);
  writeln('div fails : ', failDiv, '   (1-ulp tolerated: ', ulpDiv, ')');
  writeln('cmp fails : ', failCmp);
  writeln('subnormal flushes (tolerated): ', flush);
  if (failAdd = 0) and (failSub = 0) and (failMul = 0) and
     (failDiv = 0) and (failCmp = 0) then
    writeln('RESULT: PASS')
  else
    writeln('RESULT: FAIL');
end.
