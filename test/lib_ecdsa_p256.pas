program lib_ecdsa_p256;
{ ECDSA P-256 / SHA-256 signature verification against a generated vector.
  (Bignum-backed -> a few seconds per verify; only 2 checks to keep it bounded.) }
uses ecdsa_p256;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function Hx(const h: AnsiString): AnsiString;
var i, hi, lo: Integer;
begin
  Result := ''; i := 1;
  while i + 1 <= Length(h) do
  begin hi := Nyb(h[i]); lo := Nyb(h[i+1]); Result := Result + Chr((hi shl 4) or lo); i := i + 2; end;
end;

var qxy, sig, bad: AnsiString;
begin
  qxy := Hx('b1ab4b73b2e71321695c5aabb915904e0d83c701168326c35ceb70382ca79e1df6e6999669283857d7057b6415aec1e4fcd3f46ccc40b092f602296f5520d6b5');
  sig := Hx('2e71054a947dce3e6d1b6fa7bfa791b5a79c2fda797acc0b7a47380a0dbb4f4d69bca97149feeb0206088147f15503db6134a4291d427ae746f75883d672b521');

  SayBool('ecdsa-verify', EcdsaP256Verify(qxy, 'ecdsa test message', sig));

  bad := sig;
  bad[64] := Chr(Ord(bad[64]) xor 1);
  SayBool('ecdsa-bad-sig', not EcdsaP256Verify(qxy, 'ecdsa test message', bad));
end.
