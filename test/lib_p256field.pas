program lib_p256field;
{ Differential test: p256field (Montgomery, 4x64 saturated limbs) against
  bignum's TBigInt mod-p arithmetic.

  The two implementations share no code and were written independently -- bignum
  is base-1e9 schoolbook with an explicit BigDivMod reduction, p256field is CIOS
  Montgomery with no division at all. Agreement on pseudorandom inputs across
  add/sub/mul/sqr/inv is therefore real evidence, not a tautology.

  Runs on 32-bit targets too, where p256field's MulHiU64 takes the Pascal
  fallback -- so this doubles as the cross-target check of the whole stack. }
uses bignum, p256field;

var
  fails: Integer;
  P: TBigInt;
  rngState: UInt64;

{ --- TBigInt <-> 32 big-endian bytes --- }

function BigToBytes32(const a: TBigInt): AnsiString;
var q, r, b256, cur: TBigInt; s: AnsiString; i: Integer;
begin
  b256 := BigFromInt(256);
  SetLength(s, 32);
  cur := a;
  for i := 32 downto 1 do
  begin
    BigDivMod(cur, b256, q, r);
    if BigIsZero(r) then s[i] := Chr(0)
    else s[i] := Chr(StrToIntDef(BigToStr(r), 0));
    cur := q;
  end;
  BigToBytes32 := s;
end;

function BytesToBig32(const s: AnsiString): TBigInt;
var acc, b256, d: TBigInt; i: Integer;
begin
  acc := BigFromInt(0);
  b256 := BigFromInt(256);
  for i := 1 to Length(s) do
  begin
    acc := BigMul(acc, b256);
    d := BigFromInt(Ord(s[i]));
    acc := BigAddSigned(acc, d);
  end;
  BytesToBig32 := acc;
end;

function BigModP(const a: TBigInt): TBigInt;
var q, r: TBigInt;
begin
  BigDivMod(a, P, q, r);
  BigModP := r;
end;

{ deterministic 32-byte pseudorandom value (SplitMix64) }
function NextBytes: AnsiString;
var k, j: Integer; w: UInt64; r: AnsiString;
begin
  SetLength(r, 32);
  for k := 0 to 3 do
  begin
    rngState := rngState + UInt64($9E3779B97F4A7C15);
    w := rngState;
    w := (w xor (w shr 30)) * UInt64($BF58476D1CE4E5B9);
    w := (w xor (w shr 27)) * UInt64($94D049BB133111EB);
    w := w xor (w shr 31);
    for j := 0 to 7 do
    begin
      r[32 - 8 * k - j] := Chr(Integer(w and $FF));
      w := w shr 8;
    end;
  end;
  NextBytes := r;
end;

{ Compare a field element against a TBigInt reference value (mod p). }
procedure Expect(const got: TFe; const want: TBigInt; const what: AnsiString);
var gs, ws: AnsiString;
begin
  gs := FeToBytes(got);
  ws := BigToBytes32(BigModP(want));
  if gs <> ws then
  begin
    WriteLn('FAIL ', what);
    Inc(fails);
  end;
end;

var
  i: Integer;
  ab, bb, s: AnsiString;
  fa, fb, fr, fone: TFe;
  ba, bbig, br: TBigInt;

begin
  fails := 0;
  { p = 2^256 - 2^224 + 2^192 + 2^96 - 1 }
  P := BigFromStr('115792089210356248762697446949407573530086143415290314195533631308867097853951');

  { --- fixed sanity --- }
  FeSetOne(fone);
  FeMul(fr, fone, fone);
  if not FeEqual(fr, fone) then begin WriteLn('FAIL one*one'); Inc(fails); end;

  FeSetInt(fa, 2);
  FeSetInt(fb, 3);
  FeMul(fr, fa, fb);
  FeSetInt(fa, 6);
  if not FeEqual(fr, fa) then begin WriteLn('FAIL 2*3=6'); Inc(fails); end;

  { p-1 is a valid element; p itself is not }
  s := BigToBytes32(BigSubSigned(P, BigFromInt(1)));
  if not FeBytesInRange(s) then begin WriteLn('FAIL p-1 must be in range'); Inc(fails); end;
  s := BigToBytes32(P);
  if FeBytesInRange(s) then begin WriteLn('FAIL p must be out of range'); Inc(fails); end;

  { p-1 + 1 = 0 mod p -- the add's conditional-subtract boundary }
  s := BigToBytes32(BigSubSigned(P, BigFromInt(1)));
  FeFromBytes(fa, s);
  FeAdd(fr, fa, fone);
  if not FeIsZero(fr) then begin WriteLn('FAIL (p-1)+1 <> 0'); Inc(fails); end;

  { 0 - 1 = p-1 -- the sub's borrow/add-back boundary }
  FeSetZero(fa);
  FeSub(fr, fa, fone);
  FeFromBytes(fb, s);
  if not FeEqual(fr, fb) then begin WriteLn('FAIL 0-1 <> p-1'); Inc(fails); end;

  { --- differential sweep against bignum --- }
  rngState := UInt64($123456789ABCDEF0);
  for i := 1 to 60 do
  begin
    ab := NextBytes;
    bb := NextBytes;

    ba   := BigModP(BytesToBig32(ab));
    bbig := BigModP(BytesToBig32(bb));

    { feed the REDUCED values in, so both sides start from the same number }
    ab := BigToBytes32(ba);
    bb := BigToBytes32(bbig);
    FeFromBytes(fa, ab);
    FeFromBytes(fb, bb);

    if FeToBytes(fa) <> ab then begin WriteLn('FAIL roundtrip ', i); Inc(fails); end;

    FeAdd(fr, fa, fb);
    Expect(fr, BigAddSigned(ba, bbig), 'add');

    FeSub(fr, fa, fb);
    br := BigSubSigned(ba, bbig);
    if BigCompare(br, BigFromInt(0)) < 0 then br := BigAddSigned(br, P);
    Expect(fr, br, 'sub');

    FeMul(fr, fa, fb);
    Expect(fr, BigMul(ba, bbig), 'mul');

    FeSqr(fr, fa);
    Expect(fr, BigMul(ba, ba), 'sqr');

    { a * a^-1 = 1 -- exercises FeInv without needing a bignum modular inverse }
    FeInv(fr, fa);
    FeMul(fr, fr, fa);
    if not FeEqual(fr, fone) then begin WriteLn('FAIL inv ', i); Inc(fails); end;
  end;

  { inv(0) = 0 by convention }
  FeSetZero(fa);
  FeInv(fr, fa);
  if not FeIsZero(fr) then begin WriteLn('FAIL inv(0)'); Inc(fails); end;

  if fails = 0 then WriteLn('P256FIELD OK')
  else WriteLn('P256FIELD FAIL (', fails, ')');
end.
