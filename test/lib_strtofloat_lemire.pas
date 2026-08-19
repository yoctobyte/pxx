program lib_strtofloat_lemire;
{ Guards the Eisel-Lemire fast path in lib/rtl/sysutils.pas against CPython.

  WHY THIS EXISTS SEPARATELY FROM lib_strtofloat_roundtrip. That test proves
  FloatToStrExact(x,17) -> StrToFloat returns x, which is a strong check but
  only ever feeds the parser strings that are already the 17-digit spelling of
  a real double. Those are not the strings that break a float parser. The ones
  that do are arbitrary decimals whose value lands near a rounding boundary,
  and for those the only honest oracle is a second correctly-rounded
  implementation — CPython's float().

  It matters here specifically because the parser now carries a GENERATED
  696-entry table of 128-bit powers of ten. A single wrong digit in that table
  is invisible to every self-consistent check: the parser would simply return a
  plausible neighbouring double. This test is what makes such an entry fail.
  Verified to be capable of failing, which is the property a guard needs:
  flipping one bit in every table high word produces 191 mismatches here.

  Emits `<decimal-string> <parsed-bits-hex>` and lets the harness diff it. No
  expectation is stored in-tree — the expectation IS python3's answer, so this
  cannot drift into agreeing with a bug of our own.

  Track B (library). Gate: make lib-test. }
uses sysutils;

var seed: Int64;

function Rnd(n: Integer): Integer;
begin
  seed := (seed * 6364136223846793005 + 1442695040888963407);
  Rnd := Integer(((seed shr 33) and $7FFFFFFF) mod n);
end;

procedure Emit(const s: AnsiString);
var d: Double; b: Int64;
begin
  d := StrToFloatDef(s, 0.0);
  b := PInt64(@d)^;
  writeln(s, ' ', IntToHex(b, 16));
end;

{ nd random digits, first one nonzero }
function Digits(nd: Integer): AnsiString;
var k: Integer; s: AnsiString;
begin
  s := '';
  for k := 1 to nd do
    if k = 1 then s := s + Chr(Ord('1') + Rnd(9))
    else s := s + Chr(Ord('0') + Rnd(10));
  Digits := s;
end;

var i, q: Integer;
begin
  seed := 88172645463325252;

  { 1..19 digits over the whole decimal exponent range — the window where
    Eisel-Lemire is asked to decide, and where it ACCEPTS most of the time. }
  for i := 1 to 60000 do
  begin
    q := Rnd(700) - 350;
    Emit(Digits(1 + Rnd(19)) + 'e' + IntToStr(q));
  end;

  { The normal/subnormal boundary, where it must DECLINE and hand over to the
    exact search rather than guess with too few bits. Far fewer of these than
    of the accept cases above, and deliberately so: each one runs the exact
    ~765-digit expansion and costs ~500 us, so a large count here would buy
    little and cost the gate seconds. }
  for i := 1 to 1500 do
  begin
    q := -(300 + Rnd(40));
    Emit(Digits(1 + Rnd(19)) + 'e' + IntToStr(q));
  end;

  { More digits than a u64 significand holds: Lemire must not be reached at
    all. Same cost argument as the block above — these all take the slow path. }
  for i := 1 to 1500 do
  begin
    q := Rnd(700) - 350;
    Emit(Digits(20 + Rnd(26)) + 'e' + IntToStr(q));
  end;

  { Trailing '5' — the halfway shapes that decide round-to-even. }
  for i := 1 to 10000 do
  begin
    q := Rnd(40) - 20;
    Emit(Digits(15 + Rnd(5)) + '5e' + IntToStr(q));
  end;

  { Overflow to infinity and underflow to zero, from both sides. }
  for i := 300 to 320 do
  begin
    Emit('1e' + IntToStr(i));
    Emit('17976931348623157e' + IntToStr(i));
    Emit('-1e' + IntToStr(i));
  end;
  for i := 300 to 340 do
  begin
    Emit('1e-' + IntToStr(i));
    Emit('49406564584124654e-' + IntToStr(i));
    Emit('-1e-' + IntToStr(i));
  end;

  { The named boundaries, including the decimal that famously hung PHP's parser. }
  Emit('2.2250738585072014e-308');    { smallest normal }
  Emit('2.2250738585072011e-308');    { largest subnormal }
  Emit('1.7976931348623157e308');     { largest finite }
  Emit('4.9406564584124654e-324');    { smallest subnormal }
  Emit('0.0'); Emit('-0.0'); Emit('1.0'); Emit('-1.0'); Emit('0.5');
end.
