unit rsa;
{ RSA signature verification, PKCS#1 v1.5 with SHA-256 (rsa_pkcs1_sha256). Pure
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

end.
