unit tls13_keys;
{ TLS 1.3 key schedule (RFC 8446 §7.1) over HKDF-SHA256 — the cryptographic core
  of the handshake, milestone M6 of feature-tls13-from-scratch. Library-free
  (builds on lib/rtl/sha256). Verified against the RFC 8448 worked example.

  Only the SHA-256 ciphersuites (TLS_AES_128_GCM_SHA256 /
  TLS_CHACHA20_POLY1305_SHA256); SHA-384 suites would parameterise the hash. }

interface

{ HKDF-Expand-Label(Secret, Label, Context, Length) (RFC 8446 §7.1). `label` is
  the bare label; the "tls13 " prefix is added here. }
function HkdfExpandLabel(const secret, label, context: AnsiString; outLen: Integer): AnsiString;

{ Derive-Secret(Secret, Label, transcriptHash) — transcriptHash is the already
  computed Transcript-Hash(Messages) (32 bytes). }
function DeriveSecret(const secret, label, transcriptHash: AnsiString): AnsiString;

{ The schedule's secret chain. Zero/ecdhe are byte strings (Zero = 32 zero
  bytes when no PSK). }
function EarlySecret(const psk: AnsiString): AnsiString;
function HandshakeSecret(const earlySecret, ecdhe: AnsiString): AnsiString;
function MasterSecret(const handshakeSecret: AnsiString): AnsiString;

{ Per-direction traffic key + iv from a *_traffic_secret. }
function TrafficKey(const secret: AnsiString; keyLen: Integer): AnsiString;
function TrafficIv(const secret: AnsiString): AnsiString;

implementation

uses sha256;

function Zero32: AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to 32 do Result := Result + Chr(0);
end;

function HkdfExpandLabel(const secret, label, context: AnsiString; outLen: Integer): AnsiString;
var hl, full: AnsiString;
begin
  full := 'tls13 ' + label;
  hl := Chr((outLen shr 8) and $ff) + Chr(outLen and $ff);   { uint16 length }
  hl := hl + Chr(Length(full)) + full;                        { label, 1-byte len }
  hl := hl + Chr(Length(context)) + context;                  { context, 1-byte len }
  Result := HkdfExpand(secret, hl, outLen);
end;

function DeriveSecret(const secret, label, transcriptHash: AnsiString): AnsiString;
begin
  Result := HkdfExpandLabel(secret, label, transcriptHash, 32);
end;

function EarlySecret(const psk: AnsiString): AnsiString;
var ikm: AnsiString;
begin
  if psk = '' then ikm := Zero32 else ikm := psk;
  Result := HkdfExtract(Zero32, ikm);          { salt = 0 }
end;

function HandshakeSecret(const earlySecret, ecdhe: AnsiString): AnsiString;
var derived: AnsiString;
begin
  derived := DeriveSecret(earlySecret, 'derived', Sha256(''));
  Result := HkdfExtract(derived, ecdhe);
end;

function MasterSecret(const handshakeSecret: AnsiString): AnsiString;
var derived: AnsiString;
begin
  derived := DeriveSecret(handshakeSecret, 'derived', Sha256(''));
  Result := HkdfExtract(derived, Zero32);
end;

function TrafficKey(const secret: AnsiString; keyLen: Integer): AnsiString;
begin
  Result := HkdfExpandLabel(secret, 'key', '', keyLen);
end;

function TrafficIv(const secret: AnsiString): AnsiString;
begin
  Result := HkdfExpandLabel(secret, 'iv', '', 12);
end;

end.
