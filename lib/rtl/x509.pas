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
    Issuer:    AnsiString;   { raw issuer Name TLV (for chain linking) }
    Subject:   AnsiString;   { raw subject Name TLV }
    NotBefore: AnsiString;   { normalised YYYYMMDDHHMMSS }
    NotAfter:  AnsiString;   { normalised YYYYMMDDHHMMSS }
    ExtRaw:    AnsiString;   { raw Extensions SEQUENCE value (for SAN) }
  end;

{ Parse a DER certificate into its key fields. Result.Ok is False on malformed. }
function X509Parse(const der: AnsiString): TCert;

{ Verify `cert`'s signature under the public key in `issuer` (its KeyAlgOid +
  PubBits). For a self-signed cert pass the same cert as issuer. }
function X509VerifySig(const cert, issuer: TCert): Boolean;

{ True if nowStr (YYYYMMDDHHMMSS, UTC) is within [NotBefore, NotAfter]. }
function X509ValidAt(const cert: TCert; const nowStr: AnsiString): Boolean;

{ True if `host` matches a dNSName in the cert's subjectAltName (exact,
  case-insensitive, plus a single leading-label wildcard `*.`). }
function X509HostMatch(const cert: TCert; const host: AnsiString): Boolean;

{ Full link check: `leaf` was issued by `issuer` (name link + signature), both
  valid at nowStr, and (if host<>'') the leaf matches host. `issuer` trust (a
  root in the store) is the caller's responsibility. }
function X509VerifyChain(const leaf, issuer: TCert; const nowStr, host: AnsiString): Boolean;

implementation

uses rsa, ecdsa_p256, ed25519;

const
  OID_RSA_SHA256 = #$2a#$86#$48#$86#$f7#$0d#$01#$01#$0b;
  OID_ECDSA_SHA256 = #$2a#$86#$48#$ce#$3d#$04#$03#$02;
  OID_ED25519 = #$2b#$65#$70;
  OID_SAN = #$55#$1d#$11;       { 2.5.29.17 subjectAltName }

{ Parse a DER tag-length-value at 1-based `pos`. Returns the tag byte, the
  value's 1-based start, its length, and the position just past the value. }
procedure DerTLV(const d: AnsiString; pos: Integer;
                 var tag, vstart, vlen, nextpos: Integer);
var b, n, i: Integer;
begin
  { bounds-safe: a malformed/short element yields an empty value at the end }
  if (pos < 1) or (pos + 1 > Length(d)) then
  begin
    tag := 0; vlen := 0; vstart := Length(d) + 1; nextpos := Length(d) + 1; Exit;
  end;
  tag := Ord(d[pos]);
  b := Ord(d[pos + 1]);
  if b < $80 then
  begin
    vlen := b; vstart := pos + 2;
  end
  else
  begin
    n := b and $7f;
    if pos + 1 + n > Length(d) then
    begin
      tag := 0; vlen := 0; vstart := Length(d) + 1; nextpos := Length(d) + 1; Exit;
    end;
    vlen := 0;
    for i := 1 to n do vlen := (vlen shl 8) or Ord(d[pos + 1 + i]);
    vstart := pos + 2 + n;
  end;
  { clamp so a bogus length can't push vstart/nextpos past the buffer }
  if (vlen < 0) or (vstart + vlen > Length(d) + 1) then
    vlen := Length(d) + 1 - vstart;
  if vlen < 0 then vlen := 0;
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

{ Normalise an ASN.1 Time to YYYYMMDDHHMMSS (UTCTime gets a century prefix). }
function NormTime(tag: Integer; const t: AnsiString): AnsiString;
begin
  if tag = $17 then     { UTCTime YYMMDDHHMMSSZ }
  begin
    if t[1] < '5' then Result := '20' else Result := '19';
    Result := Result + Copy(t, 1, 12);
  end
  else                  { GeneralizedTime YYYYMMDDHHMMSSZ }
    Result := Copy(t, 1, 14);
end;

procedure ParseValidity(const der: AnsiString; vs: Integer; var nb, na: AnsiString);
var tag, ts, tl, np: Integer;
begin
  DerTLV(der, vs, tag, ts, tl, np);
  nb := NormTime(tag, Copy(der, ts, tl));
  DerTLV(der, np, tag, ts, tl, np);
  na := NormTime(tag, Copy(der, ts, tl));
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

  { --- walk tbsCertificate children --- }
  DerTLV(der, tbsPos, tag, vs, vl, np);    { tbs SEQ; vs = first child }
  p := vs;
  { optional [0] version }
  DerTLV(der, p, tag, vs, vl, np);
  if tag = $A0 then p := np;               { skip version }
  DerTLV(der, p, tag, vs, vl, np); p := np;          { serialNumber }
  DerTLV(der, p, tag, vs, vl, np); p := np;          { signature alg }
  Result.Issuer := DerElement(der, p);
  DerTLV(der, p, tag, vs, vl, np); p := np;          { issuer }
  { validity SEQUENCE of notBefore Time, notAfter Time }
  DerTLV(der, p, tag, vs, vl, np);
  ParseValidity(der, vs, Result.NotBefore, Result.NotAfter);
  p := np;
  Result.Subject := DerElement(der, p);
  DerTLV(der, p, tag, vs, vl, np); p := np;          { subject }
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

  { extensions: after SPKI, skip optional [1]/[2] unique IDs to the [3] block }
  p := bitNp;
  DerTLV(der, tbsPos, tag, vs, vl, np);    { re-read tbs end }
  while p < np do
  begin
    DerTLV(der, p, tag, vs, vl, algNp);
    if tag = $A3 then                      { [3] EXPLICIT Extensions }
    begin
      DerTLV(der, vs, tag, vs, vl, algNp); { the Extensions SEQUENCE }
      Result.ExtRaw := Copy(der, vs, vl);
      Break;
    end;
    p := algNp;
  end;

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

function X509ValidAt(const cert: TCert; const nowStr: AnsiString): Boolean;
begin
  Result := (nowStr >= cert.NotBefore) and (nowStr <= cert.NotAfter);
end;

function LowerCh(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then LowerCh := Chr(Ord(c) + 32) else LowerCh := c;
end;

function CiEq(const a, b: AnsiString): Boolean;
var i: Integer;
begin
  if Length(a) <> Length(b) then begin Result := False; Exit; end;
  for i := 1 to Length(a) do
    if LowerCh(a[i]) <> LowerCh(b[i]) then begin Result := False; Exit; end;
  Result := True;
end;

{ Match host against one dNSName, honouring a single leading `*.` wildcard. }
function NameMatch(const pat, host: AnsiString): Boolean;
var pdot, hdot: Integer; i: Integer;
begin
  if (Length(pat) > 2) and (pat[1] = '*') and (pat[2] = '.') then
  begin
    { wildcard: the part after the first host label must equal pat after `*` }
    hdot := 0;
    for i := 1 to Length(host) do if host[i] = '.' then begin hdot := i; Break; end;
    if hdot = 0 then begin Result := False; Exit; end;
    Result := CiEq(Copy(host, hdot, Length(host) - hdot + 1), Copy(pat, 2, Length(pat) - 1));
  end
  else
    Result := CiEq(pat, host);
end;

function X509HostMatch(const cert: TCert; const host: AnsiString): Boolean;
var
  ext: AnsiString;
  p, tag, vs, vl, np, endp: Integer;
  oidVs, oidVl, oidNp: Integer;
  octVs, octVl, octNp: Integer;
  gp, gtag, gvs, gvl, gnp, gend: Integer;
begin
  Result := False;
  ext := cert.ExtRaw;
  if ext = '' then Exit;
  p := 1; endp := Length(ext) + 1;
  while p < endp do
  begin
    DerTLV(ext, p, tag, vs, vl, np);              { one Extension SEQUENCE }
    if tag <> $30 then Break;
    DerTLV(ext, vs, tag, oidVs, oidVl, oidNp);    { extnID OID }
    if (tag = $06) and (Copy(ext, oidVs, oidVl) = OID_SAN) then
    begin
      { extnValue OCTET STRING is the last child of the extension }
      DerTLV(ext, oidNp, tag, octVs, octVl, octNp);
      if tag = $01 then DerTLV(ext, octNp, tag, octVs, octVl, octNp);  { skip critical BOOL }
      if tag = $04 then
      begin
        { OCTET STRING wraps a GeneralNames SEQUENCE }
        DerTLV(ext, octVs, gtag, gvs, gvl, gnp);
        gp := gvs; gend := gvs + gvl;
        while gp < gend do
        begin
          DerTLV(ext, gp, gtag, gvs, gvl, gnp);
          if gtag = $82 then                       { dNSName [2] IA5String }
            if NameMatch(Copy(ext, gvs, gvl), host) then begin Result := True; Exit; end;
          gp := gnp;
        end;
      end;
      Exit;
    end;
    p := np;
  end;
end;

function X509VerifyChain(const leaf, issuer: TCert; const nowStr, host: AnsiString): Boolean;
begin
  { cheap checks first; the signature (possibly a slow modexp) goes last }
  Result := leaf.Ok and issuer.Ok
    and (leaf.Issuer = issuer.Subject)
    and X509ValidAt(leaf, nowStr) and X509ValidAt(issuer, nowStr)
    and ((host = '') or X509HostMatch(leaf, host))
    and X509VerifySig(leaf, issuer);
end;

end.
