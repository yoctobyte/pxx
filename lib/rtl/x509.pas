unit x509;
{ Minimal X.509 / DER parsing + certificate signature verification — milestone
  M5 of feature-tls13-from-scratch. Pure Pascal over the M4 verifiers
  (rsa / ecdsa_p256 / ed25519) + sha256.

  This slice: parse a DER certificate, extract its tbsCertificate (the signed
  bytes), its signatureAlgorithm, its signatureValue, and its
  SubjectPublicKeyInfo; and verify a certificate's signature under a given
  issuer public key (so a self-signed cert verifies against its own key). Chain
  building, validity-date checks, the trust store, and hostname matching are
  follow-on slices. }

interface

type
  TCert = record
    Ok:        Boolean;
    TbsRaw:    AnsiString;   { raw tbsCertificate TLV (the signed bytes) }
    SigAlgOid: AnsiString;   { signatureAlgorithm OID value bytes }
    SigValue:  AnsiString;   { signature bits (BIT STRING content, 0x00 stripped) }
    KeyAlgOid: AnsiString;   { SPKI algorithm OID value bytes }
    PubBits:   AnsiString;   { subjectPublicKey (BIT STRING content, 0x00 stripped) }
  end;

{ Parse a DER certificate into its key fields. Result.Ok is False on malformed. }
function X509Parse(const der: AnsiString): TCert;

{ Verify `cert`'s signature under the public key in `issuer` (its KeyAlgOid +
  PubBits). For a self-signed cert pass the same cert as issuer. }
function X509VerifySig(const cert, issuer: TCert): Boolean;

implementation

uses rsa, ecdsa_p256, ed25519;

const
  OID_RSA_SHA256 = #$2a#$86#$48#$86#$f7#$0d#$01#$01#$0b;
  OID_ECDSA_SHA256 = #$2a#$86#$48#$ce#$3d#$04#$03#$02;
  OID_ED25519 = #$2b#$65#$70;

{ Parse a DER tag-length-value at 1-based `pos`. Returns the tag byte, the
  value's 1-based start, its length, and the position just past the value. }
procedure DerTLV(const d: AnsiString; pos: Integer;
                 var tag, vstart, vlen, nextpos: Integer);
var b, n, i: Integer;
begin
  tag := Ord(d[pos]);
  b := Ord(d[pos + 1]);
  if b < $80 then
  begin
    vlen := b; vstart := pos + 2;
  end
  else
  begin
    n := b and $7f;
    vlen := 0;
    for i := 1 to n do vlen := (vlen shl 8) or Ord(d[pos + 1 + i]);
    vstart := pos + 2 + n;
  end;
  nextpos := vstart + vlen;
end;

{ The whole TLV (tag..end of value) as a substring, given its start pos. }
function DerElement(const d: AnsiString; pos: Integer): AnsiString;
var tag, vs, vl, np: Integer;
begin
  DerTLV(d, pos, tag, vs, vl, np);
  Result := Copy(d, pos, np - pos);
end;

{ Strip a single leading 0x00 (DER INTEGER sign byte). }
function StripLeadZero(const s: AnsiString): AnsiString;
begin
  if (Length(s) > 1) and (Ord(s[1]) = 0) then Result := Copy(s, 2, Length(s) - 1)
  else Result := s;
end;

function LeftPad(const s: AnsiString; n: Integer): AnsiString;
var i: Integer;
begin
  Result := s;
  for i := Length(s) + 1 to n do Result := Chr(0) + Result;
end;

function X509Parse(const der: AnsiString): TCert;
var
  tag, vs, vl, np: Integer;
  certVs, tbsPos, p, spkiPos: Integer;
  algVs, algVl, algNp: Integer;
  bitTag, bitVs, bitVl, bitNp: Integer;
  i: Integer;
begin
  Result.Ok := False;
  if Length(der) < 4 then Exit;

  { outer Certificate SEQUENCE }
  DerTLV(der, 1, tag, certVs, vl, np);
  if tag <> $30 then Exit;

  { 1. tbsCertificate SEQUENCE (capture raw) }
  tbsPos := certVs;
  DerTLV(der, tbsPos, tag, vs, vl, np);
  if tag <> $30 then Exit;
  Result.TbsRaw := Copy(der, tbsPos, np - tbsPos);

  { 2. signatureAlgorithm SEQUENCE -> first child OID }
  DerTLV(der, np, tag, vs, vl, np);        { vs..= alg seq value; np advances }
  if tag <> $30 then Exit;
  DerTLV(der, vs, tag, algVs, algVl, algNp);
  if tag <> $06 then Exit;
  Result.SigAlgOid := Copy(der, algVs, algVl);

  { 3. signatureValue BIT STRING (strip leading 0x00 unused-bits byte) }
  DerTLV(der, np, tag, vs, vl, np);
  if tag <> $03 then Exit;
  Result.SigValue := Copy(der, vs + 1, vl - 1);

  { --- inside tbsCertificate: find SubjectPublicKeyInfo --- }
  DerTLV(der, tbsPos, tag, vs, vl, np);    { tbs SEQ; vs = first child }
  p := vs;
  { optional [0] version }
  DerTLV(der, p, tag, vs, vl, np);
  if tag = $A0 then p := np;               { skip version }
  { serial, sigAlg, issuer, validity, subject -> 5 elements to skip }
  for i := 1 to 5 do
  begin
    DerTLV(der, p, tag, vs, vl, np);
    p := np;
  end;
  spkiPos := p;                            { SubjectPublicKeyInfo SEQUENCE }
  DerTLV(der, spkiPos, tag, vs, vl, np);
  if tag <> $30 then Exit;
  { SPKI = algorithm-SEQ [OID, params] then subjectPublicKey BIT STRING }
  DerTLV(der, vs, tag, algVs, algVl, algNp);   { algorithm SEQ }
  if tag <> $30 then Exit;
  DerTLV(der, algVs, tag, vs, vl, np);          { OID }
  if tag <> $06 then Exit;
  Result.KeyAlgOid := Copy(der, vs, vl);
  { subjectPublicKey BIT STRING is the sibling after the algorithm SEQ }
  DerTLV(der, algNp, bitTag, bitVs, bitVl, bitNp);
  if bitTag <> $03 then Exit;
  Result.PubBits := Copy(der, bitVs + 1, bitVl - 1);   { strip 0x00 unused-bits }

  Result.Ok := True;
end;

{ Extract RSA (n, e) from a SPKI RSAPublicKey SEQUENCE. }
procedure RsaKey(const pubBits: AnsiString; var n, e: AnsiString);
var tag, vs, vl, np, p: Integer;
begin
  DerTLV(pubBits, 1, tag, vs, vl, np);     { SEQUENCE }
  p := vs;
  DerTLV(pubBits, p, tag, vs, vl, np);     { modulus INTEGER }
  n := StripLeadZero(Copy(pubBits, vs, vl));
  p := np;
  DerTLV(pubBits, p, tag, vs, vl, np);     { exponent INTEGER }
  e := StripLeadZero(Copy(pubBits, vs, vl));
end;

{ Extract ECDSA (r, s) from a signature SEQUENCE, each padded to 32 bytes. }
procedure EcdsaRS(const sigValue: AnsiString; var rs: AnsiString);
var tag, vs, vl, np, p: Integer; r, s: AnsiString;
begin
  DerTLV(sigValue, 1, tag, vs, vl, np);    { SEQUENCE }
  p := vs;
  DerTLV(sigValue, p, tag, vs, vl, np);    { r }
  r := LeftPad(StripLeadZero(Copy(sigValue, vs, vl)), 32);
  p := np;
  DerTLV(sigValue, p, tag, vs, vl, np);    { s }
  s := LeftPad(StripLeadZero(Copy(sigValue, vs, vl)), 32);
  rs := r + s;
end;

function X509VerifySig(const cert, issuer: TCert): Boolean;
var n, e, rs: AnsiString;
begin
  Result := False;
  if not (cert.Ok and issuer.Ok) then Exit;

  if cert.SigAlgOid = OID_RSA_SHA256 then
  begin
    RsaKey(issuer.PubBits, n, e);
    Result := RsaVerifyPkcs1Sha256(n, e, cert.TbsRaw, cert.SigValue);
  end
  else if cert.SigAlgOid = OID_ECDSA_SHA256 then
  begin
    EcdsaRS(cert.SigValue, rs);
    { EC SPKI key bits = 04 || X || Y; drop the 0x04 prefix }
    Result := EcdsaP256Verify(Copy(issuer.PubBits, 2, 64), cert.TbsRaw, rs);
  end
  else if cert.SigAlgOid = OID_ED25519 then
    Result := Ed25519Verify(issuer.PubBits, cert.TbsRaw, cert.SigValue);
end;

end.
