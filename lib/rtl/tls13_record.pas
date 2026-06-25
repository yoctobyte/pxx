unit tls13_record;
{ TLS 1.3 record protection (RFC 8446 §5.2) — milestone M6 of
  feature-tls13-from-scratch. Wraps a handshake/application record into a
  protected TLSCiphertext and back, over either AEAD (AES-128-GCM or
  ChaCha20-Poly1305). Library-free (builds on aesgcm / chacha20poly1305).

  Inner plaintext = content || ContentType (no padding here). Per-record nonce =
  write_iv XOR seq (seq right-aligned, big-endian). AAD = the 5-byte record
  header. }

interface

const
  TLS_AES_128_GCM       = 0;
  TLS_CHACHA20_POLY1305 = 1;

  CT_HANDSHAKE        = 22;
  CT_APPLICATION_DATA = 23;
  CT_ALERT            = 21;

{ Per-record nonce: write_iv (12 bytes) XOR seq in the low 8 bytes. }
function Tls13Nonce(const iv: AnsiString; seq: Int64): AnsiString;

{ Seal `plaintext` (of inner content type `contentType`) into a TLSCiphertext
  record (5-byte header + AEAD output). }
function Tls13Seal(suite: Integer; const key, iv: AnsiString; seq: Int64;
                   contentType: Byte; const plaintext: AnsiString): AnsiString;

{ Open a TLSCiphertext `record`. On success sets plaintext + contentType and
  returns True; on auth failure returns False. }
function Tls13Open(suite: Integer; const key, iv: AnsiString; seq: Int64;
                   const rec: AnsiString;
                   var plaintext: AnsiString; var contentType: Byte): Boolean;

implementation

uses aesgcm, chacha20poly1305;

function Tls13Nonce(const iv: AnsiString; seq: Int64): AnsiString;
var i: Integer; b: Int64;
begin
  Result := iv;                       { 12 bytes }
  b := seq;
  for i := 12 downto 5 do             { XOR seq into the last 8 bytes, big-endian }
  begin
    Result[i] := Chr(Ord(Result[i]) xor (b and $FF));
    b := b shr 8;
  end;
end;

function AeadSeal(suite: Integer; const key, nonce, aad, pt: AnsiString): AnsiString;
begin
  if suite = TLS_CHACHA20_POLY1305 then Result := Chacha20Poly1305Seal(key, nonce, aad, pt)
  else Result := AesGcmSeal(key, nonce, aad, pt);
end;

function AeadOpen(suite: Integer; const key, nonce, aad, ctTag: AnsiString;
                 var pt: AnsiString): Boolean;
begin
  if suite = TLS_CHACHA20_POLY1305 then Result := Chacha20Poly1305Open(key, nonce, aad, ctTag, pt)
  else Result := AesGcmOpen(key, nonce, aad, ctTag, pt);
end;

function Header(len: Integer): AnsiString;
begin
  { opaque_type = application_data(23), legacy_version = 0x0303, length }
  Result := Chr(CT_APPLICATION_DATA) + Chr($03) + Chr($03) +
            Chr((len shr 8) and $FF) + Chr(len and $FF);
end;

function Tls13Seal(suite: Integer; const key, iv: AnsiString; seq: Int64;
                   contentType: Byte; const plaintext: AnsiString): AnsiString;
var inner, nonce, hdr, body: AnsiString;
begin
  inner := plaintext + Chr(contentType);
  hdr   := Header(Length(inner) + 16);          { +16 AEAD tag }
  nonce := Tls13Nonce(iv, seq);
  body  := AeadSeal(suite, key, nonce, hdr, inner);
  Result := hdr + body;
end;

function Tls13Open(suite: Integer; const key, iv: AnsiString; seq: Int64;
                   const rec: AnsiString;
                   var plaintext: AnsiString; var contentType: Byte): Boolean;
var nonce, hdr, body, inner: AnsiString; i: Integer;
begin
  plaintext := ''; contentType := 0;
  Result := False;
  if Length(rec) < 5 + 16 then Exit;
  hdr   := Copy(rec, 1, 5);
  body  := Copy(rec, 6, Length(rec) - 5);
  nonce := Tls13Nonce(iv, seq);
  if not AeadOpen(suite, key, nonce, hdr, body, inner) then Exit;
  { strip trailing zero padding, then the content type byte }
  i := Length(inner);
  while (i >= 1) and (Ord(inner[i]) = 0) do i := i - 1;
  if i < 1 then Exit;
  contentType := Ord(inner[i]);
  plaintext := Copy(inner, 1, i - 1);
  Result := True;
end;

end.
