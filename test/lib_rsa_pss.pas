{ RSASSA-PSS / SHA-256 verification against an OpenSSL-produced signature.
  rsa_pss_rsae_sha256 (0x0804) is the scheme TLS 1.3 REQUIRES for an RSA
  CertificateVerify -- RFC 8446 4.4.3 forbids the PKCS#1 v1.5 schemes there --
  so without this a from-scratch client cannot authenticate an RSA server.

  The key, message and signature below came from

    openssl genrsa -out k.pem 2048
    openssl dgst -sha256 -sigopt rsa_padding_mode:pss \
            -sigopt rsa_pss_saltlen:32 -sign k.pem -out sig.bin msg.bin

  so the positive case is OpenSSL's output, not ours. PSS is randomised (a
  fresh salt per signature), which is why the vector is pinned rather than
  regenerated: the point is that a verifier accepts a signature it did not make.

  The negative cases carry as much weight as the positive one -- a verifier
  that returns True unconditionally passes any single positive test. }
program lib_rsa_pss;
uses rsa;

var fails: Integer;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - 48
  else if (c >= 'a') and (c <= 'f') then Nyb := Ord(c) - 87
  else Nyb := Ord(c) - 55;
end;

function Hex2Bin(const h: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  i := 1;
  while i + 1 <= Length(h) do
  begin
    r := r + Chr(Nyb(h[i]) * 16 + Nyb(h[i + 1]));
    i := i + 2;
  end;
  Hex2Bin := r;
end;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL'); fails := fails + 1; end;
end;

const
  N_HEX   = 'bb25f5d50c72c213324d59dc8264b32aeaac9e1144dcfb2288ba88d98afa191d5c104cf3533d2b831bd14b94909ff41c7f0d267656dde23bdb22f571511c9b5d8565d88c94b956bb63417257c6bf82662bf20f45a9549e183c287062ad9ec4c1e711a7f4d643c2a6391f45d0ae827e42576c20f4965aaf1403c587affadb7d9ce80b74bc02a4e210c630eb0351e60c2601b35884b86ecccd1e8d4dd1ef86b1d28e0668d265d445e10ad62c965def4c9967496867c0e3cedcc6cf8451f530d34e91c4701e52cdee651b0aa82d98d39a04b41645ba8651ad98314f0d82e3b90e4f3efe2bfbf44f379499a6f95f614cd67e539046a16c8b948bbd09d4e5fa78a32d';
  SIG_HEX = 'a2977351483d26295bb1c3fdf0c7f46a8160ad48b2b5405b7da00dbfddd06e4c05dbb9380e0aeb09c5ccd244631527f94db456d826c7bcc803d15604a44603e193652ed83bcef08cbde28c08df6598240820519ff5a49ee5205c987b38f8a86856b46123d083c45d6f0a680853c6f4b6e29be7c50a2f31c4b6ea49d542581000e6fcc74bbdf41f9e84d84f6ce8bb23d5652b3c7755be5d142ca40236c8b340052c9189b02bb6e9dc607cd156db5346fd5fcd6f7a5f10a4e9077f5f701ed09afcf548167f987ed4a24319e365b50c4a516c621bcbfe792098216acd4a03e293382486d7442e8b984b75dffb815794d7859263c926439647154f8046c3f63daa37';
  MSG     = 'TLS 1.3 CertificateVerify probe';
var
  n, e, sig, bad: AnsiString;
begin
  fails := 0;
  n := Hex2Bin(N_HEX);
  e := Chr($01) + Chr($00) + Chr($01);          { 65537 }
  sig := Hex2Bin(SIG_HEX);

  { OpenSSL's own signature must verify }
  Chk('valid',    RsaVerifyPssSha256(n, e, MSG, sig),            True);
  { a different message must not }
  Chk('wrongmsg', RsaVerifyPssSha256(n, e, MSG + '!', sig),      False);
  { a flipped signature bit must not -- catches a verifier that ignores sig }
  bad := sig;
  bad[100] := Chr(Ord(bad[100]) xor 1);
  Chk('bitflip',  RsaVerifyPssSha256(n, e, MSG, bad),            False);
  { the 0xBC trailer is load-bearing }
  bad := sig;
  bad[Length(bad)] := Chr(Ord(bad[Length(bad)]) xor $FF);
  Chk('trailer',  RsaVerifyPssSha256(n, e, MSG, bad),            False);
  { a truncated or empty signature must be rejected, not read out of bounds }
  Chk('short',    RsaVerifyPssSha256(n, e, MSG, Copy(sig, 1, 255)), False);
  Chk('empty',    RsaVerifyPssSha256(n, e, MSG, ''),             False);
  { PSS and PKCS#1 v1.5 are different encodings of the same key }
  Chk('notpkcs1', RsaVerifyPkcs1Sha256(n, e, MSG, sig),          False);

  if fails = 0 then WriteLn('RSAPSS OK')
  else WriteLn('RSAPSS FAILED ', fails);
end.
