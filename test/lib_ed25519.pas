program lib_ed25519;
{ Ed25519 signature verification (RFC 8032) against a generated vector. }
uses ed25519;

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

var pub, sig, badSig: AnsiString;
begin
  pub := Hx('189d5f5261f5276048c4452ba6d294c5a1335537bc6b7a9bdeb4fca8ae33e279');
  sig := Hx('7401af3835964cb7a817b50373241f8c7db86adf13d968489a882036b09aee51e17da763c4364cf41e24cc9874589cef1a5c6bb3cd2b222cae7eeeb000e3b300');

  SayBool('ed25519-verify', Ed25519Verify(pub, 'hello ed25519', sig));
  SayBool('ed25519-wrong-msg', not Ed25519Verify(pub, 'hello ed25518', sig));

  badSig := sig;
  badSig[64] := Chr(Ord(badSig[64]) xor 1);
  SayBool('ed25519-bad-sig', not Ed25519Verify(pub, 'hello ed25519', badSig));
end.
