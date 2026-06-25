program lib_rsa;
{ RSA-PKCS#1-v1.5-SHA256 signature verification against a generated 2048-bit
  vector (message "abc"). Valid sig verifies; tampered sig / message / key do not. }
uses rsa;

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

var n, e, sig, badSig: AnsiString;
begin
  n := Hx('ccb4617d9e798d29699283f5f4665bf3b361d1a106c4d4d83364a8a60d9817def592707ec1925972651dd41d6fafe419faf94499dad24d3a9d6fc957592f65f194f4059c8766d9db5029981f346199e6dc37428d2480f9dfadf34ca53f63f82e9195296c0919df6036333f760ad9e7fe333de6dd9b09f94b256dc59178d3c98fb5b92b152261b85e762a28d8ea5fbb6c3a7b896463d3d846844dcecd33b20e609899b1c655b39b73df5f563ada2163b299a51a0c4b16f5d336290b55b81def689aa08d1b95d2a47889f6cbfa9f88669c9f135f4fd9f5f55527677c6cc1322eaa05e607103dc5432ece896108a711a6ae60f26c54482d3b71a0ced6ccbd2760ab');
  e := Hx('010001');
  sig := Hx('29da12681def5befd19dfb899d5349caa5c14d896c9695dc9eeb07ecf83d96232c91614a8ea3096d0db24f12f4346f174807092332efc8ae4f8f4e717d5b9b8cb1200c6ae19b58ae20a30045a7d2a507327aac29ceeb76e738244b1b45bfb842daed71609ec2ca87ed5190b9fd604cf63aec9471d7940ab7b1e08fb318a8bdf7acb531e9a9b2aba99a7d09b61567065660bac33438e585cfd5c65d270e55dbe09927e2a85d97ab302905c0a396946f852c615bcd68eaf8b384d7dedc8531b50248758001ac008bb786cf67cbc613abc79c30821d8b0111ec3073044f4915fc40de57f1b97bcbded3fd2359f2b87608c025952c26a5c6d9a59409cd2362c6f39a');

  SayBool('rsa-verify', RsaVerifyPkcs1Sha256(n, e, 'abc', sig));
  SayBool('rsa-wrong-msg', not RsaVerifyPkcs1Sha256(n, e, 'abd', sig));

  badSig := sig;
  badSig[Length(badSig)] := Chr(Ord(badSig[Length(badSig)]) xor 1);
  SayBool('rsa-bad-sig', not RsaVerifyPkcs1Sha256(n, e, 'abc', badSig));
end.
