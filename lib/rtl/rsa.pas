{ SPDX-License-Identifier: Zlib }
unit rsa;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ RSA signature verification: PKCS#1 v1.5 and PSS, both with SHA-256. Pure
  Pascal over lib/rtl/bignum + lib/rtl/sha256 — part of milestone M4 of
  feature-tls13-from-scratch (verifying a server certificate's RSA signature).

  Verify only (no signing / key generation). Inputs are big-endian byte strings
  (AnsiString): the modulus n and public exponent e from the cert's public key,
  the message, and the signature. Small public exponent (typically 65537) keeps
  the modexp cheap even on the base-1e9 bignum. }

interface

{ True iff `sig` is a valid PKCS#1 v1.5 / SHA-256 signature of `msg` under the
  RSA public key (`n`, `e`), all big-endian byte strings. }
function RsaVerifyPkcs1Sha256(const n, e, msg, sig: AnsiString): Boolean;

{ True iff `sig` is a valid RSASSA-PSS / SHA-256 signature of `msg` under the
  RSA public key (`n`, `e`), with MGF1-SHA256 and a 32-byte salt — which is
  rsa_pss_rsae_sha256 (0x0804), the scheme TLS 1.3 REQUIRES for an RSA
  CertificateVerify. RFC 8446 4.4.3 forbids the PKCS#1 v1.5 schemes there
  outright, so a TLS 1.3 client that only has the function above cannot verify
  an RSA server at all. RFC 8017 8.1.2 + 9.1.2. }
function RsaVerifyPssSha256(const n, e, msg, sig: AnsiString): Boolean;

implementation

uses bignum, sha256, sysutils;

{ big-endian bytes -> bignum. Accumulates in a local (managed-record Result used
  as a call arg in its own reassignment miscompiles — bug-managed-record-result-
  self-arg). }
function BytesToBig(const s: AnsiString): TBigInt;
var acc, t, d: TBigInt; i: Integer;
begin
  acc := BigFromInt(0);
  for i := 1 to Length(s) do
  begin
    t := BigMulSmall(acc, 256);
    d := BigFromInt(Ord(s[i]));
    acc := BigAdd(t, d);
  end;
  Result := acc;
end;

{ bignum -> k big-endian bytes (left zero-padded). }
function BigToBytes(a: TBigInt; k: Integer): AnsiString;
var q, r, b256: TBigInt; i: Integer;
begin
  SetLength(Result, k);
  b256 := BigFromInt(256);
  for i := k downto 1 do
  begin
    BigDivMod(a, b256, q, r);
    Result[i] := Chr(StrToInt(BigToStr(r)) and $FF);
    a := q;
  end;
end;

function RsaVerifyPkcs1Sha256(const n, e, msg, sig: AnsiString): Boolean;
const
  { DigestInfo prefix for SHA-256 (DER of the algorithm id + 0x04 0x20). }
  DI: array[0..18] of Byte = (
    $30,$31,$30,$0d,$06,$09,$60,$86,$48,$01,$65,$03,$04,$02,$01,$05,$00,$04,$20);
var
  nBig, eBig, sigBig, m: TBigInt;
  k, i, diff, psLen: Integer;
  em, expected, digest: AnsiString;
begin
  Result := False;
  k := Length(n);
  if (k < 3 + 19 + 32) or (Length(sig) <> k) then Exit;

  nBig   := BytesToBig(n);
  eBig   := BytesToBig(e);
  sigBig := BytesToBig(sig);
  if BigCompare(sigBig, nBig) >= 0 then Exit;       { sig must be in [0, n) }

  m  := BigModPow(sigBig, eBig, nBig);              { s^e mod n }
  em := BigToBytes(m, k);

  { expected EM = 00 01 (FF * psLen) 00 || DigestInfo || H(msg) }
  digest := Sha256(msg);
  psLen  := k - 3 - 19 - 32;
  expected := Chr(0) + Chr(1);
  for i := 1 to psLen do expected := expected + Chr($FF);
  expected := expected + Chr(0);
  for i := 0 to 18 do expected := expected + Chr(DI[i]);
  expected := expected + digest;

  { constant-time-ish compare }
  if Length(em) <> Length(expected) then Exit;
  diff := 0;
  for i := 1 to Length(em) do diff := diff or (Ord(em[i]) xor Ord(expected[i]));
  Result := diff = 0;
end;

{ MGF1 with SHA-256 (RFC 8017 B.2.1): T = H(seed || counter) repeated, truncated
  to maskLen. The counter is a 4-byte big-endian word starting at zero. }
function Mgf1Sha256(const seed: AnsiString; maskLen: Integer): AnsiString;
var t, c: AnsiString; counter: Integer;
begin
  t := '';
  counter := 0;
  while Length(t) < maskLen do
  begin
    c := Chr((counter shr 24) and $FF) + Chr((counter shr 16) and $FF) +
         Chr((counter shr 8) and $FF) + Chr(counter and $FF);
    t := t + Sha256(seed + c);
    counter := counter + 1;
  end;
  Result := Copy(t, 1, maskLen);
end;

function RsaVerifyPssSha256(const n, e, msg, sig: AnsiString): Boolean;
const
  HLEN = 32;      { SHA-256 }
  SLEN = 32;      { salt length; rsa_pss_rsae_sha256 uses hLen }
var
  nBig, eBig, sigBig, m: TBigInt;
  k, i, emLen, emBits, dbLen, topBits, diff: Integer;
  em, maskedDB, h, dbMask, db, salt, mPrime, hPrime, mHash: AnsiString;
begin
  Result := False;
  k := Length(n);
  if (k = 0) or (Length(sig) <> k) then Exit;

  { emBits = modBits - 1, so emLen can be one byte shorter than k when the
    modulus's top byte has its high bit set (the usual 2048-bit case keeps
    emLen = k). Derive modBits from the leading byte rather than assuming. }
  i := 1;
  while (i <= k) and (Ord(n[i]) = 0) do i := i + 1;
  if i > k then Exit;                          { modulus is zero }
  emBits := (k - i + 1) * 8;
  topBits := Ord(n[i]);
  while (topBits and $80) = 0 do
  begin
    emBits := emBits - 1;
    topBits := topBits shl 1;
  end;
  emBits := emBits - 1;                        { modBits - 1 }
  emLen := (emBits + 7) div 8;
  if emLen < HLEN + SLEN + 2 then Exit;        { RFC 8017: inconsistent }

  nBig   := BytesToBig(n);
  eBig   := BytesToBig(e);
  sigBig := BytesToBig(sig);
  if BigCompare(sigBig, nBig) >= 0 then Exit;  { sig must be in [0, n) }

  m  := BigModPow(sigBig, eBig, nBig);         { s^e mod n }
  em := BigToBytes(m, emLen);

  if Ord(em[emLen]) <> $BC then Exit;          { trailer field }

  dbLen    := emLen - HLEN - 1;
  maskedDB := Copy(em, 1, dbLen);
  h        := Copy(em, dbLen + 1, HLEN);

  { the leftmost 8*emLen - emBits bits of maskedDB must be zero }
  topBits := 8 * emLen - emBits;
  if topBits > 0 then
    if (Ord(maskedDB[1]) shr (8 - topBits)) <> 0 then Exit;

  dbMask := Mgf1Sha256(h, dbLen);
  db := '';
  for i := 1 to dbLen do
    db := db + Chr(Ord(maskedDB[i]) xor Ord(dbMask[i]));
  if topBits > 0 then
    db[1] := Chr(Ord(db[1]) and ($FF shr topBits));

  { DB must be PS (all zero) || 0x01 || salt }
  for i := 1 to dbLen - SLEN - 1 do
    if Ord(db[i]) <> 0 then Exit;
  if Ord(db[dbLen - SLEN]) <> 1 then Exit;
  salt := Copy(db, dbLen - SLEN + 1, SLEN);

  mHash := Sha256(msg);
  mPrime := '';
  for i := 1 to 8 do mPrime := mPrime + Chr(0);
  mPrime := mPrime + mHash + salt;
  hPrime := Sha256(mPrime);

  diff := 0;
  for i := 1 to HLEN do diff := diff or (Ord(h[i]) xor Ord(hPrime[i]));
  Result := diff = 0;
end;

end.
