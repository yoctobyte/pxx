program test_softfloat_double;
{ Standalone validation of the soft-double kernels in compiler/builtin/softfloat.pas.
  Native double on x86-64 is true IEEE binary64 (hardware), so it is an exact
  oracle for every op including division (correctly rounded) — exact bit-pattern
  match is required, no ulp slack. Operates on a grid of double encodings plus a
  large randomized normal-range sweep. Also checks i2d/d2i and the single<->double
  repacks s2d/d2s. Float fn params/returns are storage-only and unreliable, so the
  oracle writes/reads bit patterns straight through typed pointers into locals. }

uses softfloat;

type
  PInt64 = ^Int64;
  PDouble = ^Double;
  PLongWord = ^LongWord;
  PSingle = ^Single;

const
  NGRID = 21;

var
  grid: array[0..NGRID-1] of Int64;
  failAdd, failSub, failMul, failDiv, failCmp: Integer;
  rngState: LongWord;

function dIsNaNBits(w: Int64): Boolean;
begin
  dIsNaNBits := (((w shr 52) and $7FF) = $7FF) and ((w and ((Int64(1) shl 52) - 1)) <> 0);
end;

{ subnormal double (exp field 0, non-zero mantissa) — kernel flushes these to 0 }
function dIsSubnormal(w: Int64): Boolean;
begin
  dIsSubnormal := (((w shr 52) and $7FF) = 0) and ((w and ((Int64(1) shl 52) - 1)) <> 0);
end;

{ documented flush-to-zero: kernel returns signed 0 where native rounded subnormal }
function dFlushOK(soft: Int64; nat: Int64): Boolean;
begin
  dFlushOK := ((soft and ((Int64(1) shl 63) - 1)) = 0) and dIsSubnormal(nat);
end;

procedure InitGrid;
begin
  grid[0]  := $0000000000000000;   { +0 }
  grid[1]  := Int64(1) shl 63;      { -0 }
  grid[2]  := $3FF0000000000000;   { 1.0 }
  grid[3]  := $BFF0000000000000;   { -1.0 }
  grid[4]  := $4000000000000000;   { 2.0 }
  grid[5]  := $3FE0000000000000;   { 0.5 }
  grid[6]  := $400921FB54442D18;   { pi }
  grid[7]  := $C00921FB54442D18;   { -pi }
  grid[8]  := $3FB999999999999A;   { 0.1 }
  grid[9]  := $4202A05F20000000;   { 1e10 }
  grid[10] := $3DDB7CDFD9D7BDBB;   { 1e-10 }
  grid[11] := $7E37E43C8800759C;   { 1e300 }
  grid[12] := $01A56E1FC2F8F359;   { 1e-300 }
  grid[13] := $4330000000000000;   { 2^52 }
  grid[14] := $4330000000000001;   { 2^52 + 1 }
  grid[15] := $40FE240000000000;   { 123456.0 }
  grid[16] := $C0C3880000000000;   { -10000.0 }
  grid[17] := Int64($7FF0000000000000);   { +Inf }
  grid[18] := Int64($FFF0000000000000);   { -Inf }
  grid[19] := Int64($7FF8000000000000);   { NaN }
  grid[20] := $3FF8000000000000;   { 1.5 }
end;

function NextRand: LongWord;
begin
  rngState := (rngState * 1103515245) + 12345;
  NextRand := rngState;
end;

function RandNormalDouble: Int64;
var e, sgn: Int64; mant: Int64;
begin
  e := NextRand and $7FF;
  if e = 0 then e := 1;
  if e >= 2046 then e := 2045;   { keep exp in [1..2045] (no inf/nan) }
  mant := ((Int64(NextRand) and $FFFFF) shl 32) or (Int64(NextRand) and $FFFFFFFF);
  sgn := NextRand and 1;
  RandNormalDouble := (sgn shl 63) or (e shl 52) or mant;
end;

procedure CheckOne(ba: Int64; bb: Int64);
var
  da, db, dc: Double;
  soft, nat: Int64;
  pd: PDouble;
  pi: PInt64;
  sc, nc: Integer;
begin
  pi := PInt64(@da); pi^ := ba;
  pi := PInt64(@db); pi^ := bb;

  dc := da + db; soft := __pxx_dadd(ba, bb);
  pi := PInt64(@dc); nat := pi^;
  if not (dIsNaNBits(soft) and dIsNaNBits(nat)) then
    if (soft <> nat) and not dFlushOK(soft, nat) then
    begin failAdd := failAdd + 1; if failAdd <= 6 then writeln('ADD a=', ba, ' b=', bb, ' s=', soft, ' n=', nat); end;

  dc := da - db; soft := __pxx_dsub(ba, bb);
  pi := PInt64(@dc); nat := pi^;
  if not (dIsNaNBits(soft) and dIsNaNBits(nat)) then
    if (soft <> nat) and not dFlushOK(soft, nat) then
    begin failSub := failSub + 1; if failSub <= 6 then writeln('SUB a=', ba, ' b=', bb, ' s=', soft, ' n=', nat); end;

  dc := da * db; soft := __pxx_dmul(ba, bb);
  pi := PInt64(@dc); nat := pi^;
  if not (dIsNaNBits(soft) and dIsNaNBits(nat)) then
    if (soft <> nat) and not dFlushOK(soft, nat) then
    begin failMul := failMul + 1; if failMul <= 6 then writeln('MUL a=', ba, ' b=', bb, ' s=', soft, ' n=', nat); end;

  dc := da / db; soft := __pxx_ddiv(ba, bb);
  pi := PInt64(@dc); nat := pi^;
  if not (dIsNaNBits(soft) and dIsNaNBits(nat)) then
    if (soft <> nat) and not dFlushOK(soft, nat) then
    begin failDiv := failDiv + 1; if failDiv <= 8 then writeln('DIV a=', ba, ' b=', bb, ' s=', soft, ' n=', nat); end;

  sc := __pxx_dcmp(ba, bb);
  if dIsNaNBits(ba) or dIsNaNBits(bb) then nc := 2
  else if da < db then nc := -1
  else if da > db then nc := 1
  else nc := 0;
  if sc <> nc then
  begin failCmp := failCmp + 1; if failCmp <= 8 then writeln('CMP a=', ba, ' b=', bb, ' s=', sc, ' n=', nc); end;
end;

procedure CheckConversions;
var
  ints: array[0..10] of Integer;
  i, k, back: Integer;
  s, nat: Int64;
  d: Double;
  pd: PDouble;
  pi: PInt64;
begin
  ints[0] := 0;   ints[1] := 1;     ints[2] := -1;    ints[3] := 2;
  ints[4] := 100; ints[5] := -100;  ints[6] := 123456; ints[7] := -987654;
  ints[8] := 16777216; ints[9] := 2147483647; ints[10] := -2147483648;
  for i := 0 to 10 do
  begin
    k := ints[i];
    s := __pxx_i2d(k);
    d := k;                       { native int -> double (exact) }
    pi := PInt64(@d); nat := pi^;
    if s <> nat then writeln('I2D ', k, ' s=', s, ' n=', nat);
    back := __pxx_d2i(s);
    if back <> k then writeln('D2I k=', k, ' back=', back);
  end;
end;

procedure CheckRepack;
var
  t: Integer;
  sb, d2sExp: LongWord;
  db, s2dExp: Int64;
  sv: Single;
  dv: Double;
  ps: PSingle; pl: PLongWord;
  pi: PInt64; pd: PDouble;
  fails: Integer;
begin
  fails := 0;
  for t := 1 to 50000 do
  begin
    { s2d: random normal single -> double, vs native widening }
    sb := (NextRand and 1) shl 31;
    sb := sb or ((NextRand and $FE) + 1) shl 23;   { exp in [1..254]-ish, avoid 0/255 }
    sb := sb or (NextRand and $7FFFFF);
    { recompute cleanly to guarantee exp in [1,254] }
    sb := ((NextRand and 1) shl 31) or (((NextRand and $FD) + 1) shl 23) or (NextRand and $7FFFFF);
    pl := PLongWord(@sv); pl^ := sb;
    dv := sv;                       { native single -> double }
    pi := PInt64(@dv); s2dExp := pi^;
    db := __pxx_s2d(sb);
    if db <> s2dExp then
    begin fails := fails + 1; if fails <= 6 then writeln('S2D sb=', sb, ' s=', db, ' n=', s2dExp); end;

    { d2s: random normal double -> single, vs native narrowing }
    db := RandNormalDouble;
    pi := PInt64(@dv); pi^ := db;
    sv := dv;                       { native double -> single (rounds) }
    pl := PLongWord(@sv); d2sExp := pl^;
    sb := __pxx_d2s(db);
    { tolerate subnormal flush (soft -> signed zero where native subnormal) }
    if (sb <> d2sExp) and
       not (((sb and $7FFFFFFF) = 0) and (((d2sExp and $7F800000) = 0) and ((d2sExp and $7FFFFF) <> 0))) then
    begin fails := fails + 1; if fails <= 12 then writeln('D2S db=', db, ' s=', sb, ' n=', d2sExp); end;
  end;
  writeln('repack fails: ', fails);
end;

procedure CheckRandom(n: Integer);
var t: Integer; ba, bb: Int64;
begin
  for t := 1 to n do
  begin
    ba := RandNormalDouble;
    bb := RandNormalDouble;
    CheckOne(ba, bb);
  end;
end;

var i, j: Integer;
begin
  failAdd := 0; failSub := 0; failMul := 0; failDiv := 0; failCmp := 0;
  InitGrid;
  for i := 0 to NGRID-1 do
    for j := 0 to NGRID-1 do
      CheckOne(grid[i], grid[j]);

  CheckConversions;

  rngState := 2463534242;
  CheckRandom(200000);
  CheckRepack;

  writeln('---');
  writeln('add fails : ', failAdd);
  writeln('sub fails : ', failSub);
  writeln('mul fails : ', failMul);
  writeln('div fails : ', failDiv);
  writeln('cmp fails : ', failCmp);
  if (failAdd = 0) and (failSub = 0) and (failMul = 0) and
     (failDiv = 0) and (failCmp = 0) then
    writeln('RESULT: PASS')
  else
    writeln('RESULT: FAIL');
end.
