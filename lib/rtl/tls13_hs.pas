{ SPDX-License-Identifier: Zlib }
unit tls13_hs;
{ TLS 1.3 handshake messages (RFC 8446 §4) — the ClientHello builder and the
  ServerHello parser, plus small framing helpers and the transcript hash.
  Milestone M6 of feature-tls13-from-scratch. Library-free (on sha256).

  X25519-only key exchange, AES-128-GCM + ChaCha20-Poly1305 ciphersuites,
  signature_algorithms covering the M4 verifiers. }

interface

uses sha256;

const
  HS_CLIENT_HELLO = 1;
  HS_SERVER_HELLO = 2;
  HS_ENCRYPTED_EXTENSIONS = 8;
  HS_CERTIFICATE = 11;
  HS_CERTIFICATE_VERIFY = 15;
  HS_FINISHED = 20;

  CS_AES_128_GCM_SHA256   = $1301;
  CS_CHACHA20_POLY1305    = $1303;

{ Wrap a handshake message body: type(1) || length(3) || body. }
function HsWrap(msgType: Byte; const body: AnsiString): AnsiString;

{ Read a handshake message at 1-based `pos`: type, body, and next position. }
procedure HsRead(const buf: AnsiString; pos: Integer;
                 var msgType: Byte; var body: AnsiString; var nextpos: Integer);

{ Build a ClientHello handshake message. random/x25519pub are raw bytes (32
  each); serverName is the SNI host (may be ''). }
function BuildClientHello(const random32, x25519pub: AnsiString;
                          const serverName: AnsiString): AnsiString;

{ Parse a ServerHello body. Returns False if malformed. Extracts the chosen
  cipher suite and the server's X25519 key_share. }
function ParseServerHello(const body: AnsiString;
                          var cipherSuite: Integer; var serverKeyShare: AnsiString): Boolean;

{ Transcript-Hash over the concatenated handshake messages (SHA-256). }
function TranscriptHash(const messages: AnsiString): AnsiString;

implementation

function U16(v: Integer): AnsiString;
begin Result := Chr((v shr 8) and $FF) + Chr(v and $FF); end;

function U24(v: Integer): AnsiString;
begin Result := Chr((v shr 16) and $FF) + Chr((v shr 8) and $FF) + Chr(v and $FF); end;

function HsWrap(msgType: Byte; const body: AnsiString): AnsiString;
begin Result := Chr(msgType) + U24(Length(body)) + body; end;

procedure HsRead(const buf: AnsiString; pos: Integer;
                 var msgType: Byte; var body: AnsiString; var nextpos: Integer);
var len: Integer;
begin
  msgType := Ord(buf[pos]);
  len := (Ord(buf[pos+1]) shl 16) or (Ord(buf[pos+2]) shl 8) or Ord(buf[pos+3]);
  body := Copy(buf, pos + 4, len);
  nextpos := pos + 4 + len;
end;

{ length-prefixed helpers }
function Vec8(const s: AnsiString): AnsiString;
begin Result := Chr(Length(s)) + s; end;

function Vec16(const s: AnsiString): AnsiString;
begin Result := U16(Length(s)) + s; end;

function Ext(extType: Integer; const data: AnsiString): AnsiString;
begin Result := U16(extType) + Vec16(data); end;

function BuildClientHello(const random32, x25519pub: AnsiString;
                          const serverName: AnsiString): AnsiString;
var exts, body, ks, sni: AnsiString;
begin
  exts := '';

  { server_name (0) }
  if serverName <> '' then
  begin
    sni := Chr(0) + Vec16(serverName);        { name_type=host_name(0) + HostName }
    exts := exts + Ext(0, Vec16(sni));
  end;

  { supported_versions (43): list of one, TLS 1.3 (0304) }
  exts := exts + Ext(43, Vec8(U16($0304)));

  { supported_groups (10): X25519 (001d) }
  exts := exts + Ext(10, Vec16(U16($001d)));

  { signature_algorithms (13): ed25519, ecdsa_p256_sha256, rsa_pss_sha256, rsa_pkcs1_sha256 }
  exts := exts + Ext(13, Vec16(U16($0807) + U16($0403) + U16($0804) + U16($0401)));

  { key_share (51): one X25519 entry }
  ks := U16($001d) + Vec16(x25519pub);        { group + key_exchange }
  exts := exts + Ext(51, Vec16(ks));

  body := U16($0303)                          { legacy_version }
        + random32                            { random (32) }
        + Vec8('')                            { legacy_session_id (empty) }
        + Vec16(U16(CS_AES_128_GCM_SHA256) + U16(CS_CHACHA20_POLY1305))  { cipher_suites }
        + Vec8(Chr(0))                        { legacy_compression_methods = null }
        + Vec16(exts);

  Result := HsWrap(HS_CLIENT_HELLO, body);
end;

function ParseServerHello(const body: AnsiString;
                          var cipherSuite: Integer; var serverKeyShare: AnsiString): Boolean;
var p, sidLen, extsLen, extEnd, etype, elen, group: Integer;
begin
  Result := False;
  cipherSuite := 0; serverKeyShare := '';
  if Length(body) < 38 then Exit;
  p := 1;
  p := p + 2;                                 { legacy_version }
  p := p + 32;                                { random }
  sidLen := Ord(body[p]); p := p + 1 + sidLen;{ legacy_session_id }
  cipherSuite := (Ord(body[p]) shl 8) or Ord(body[p+1]); p := p + 2;
  p := p + 1;                                 { legacy_compression_method }
  if p + 1 > Length(body) then Exit;
  extsLen := (Ord(body[p]) shl 8) or Ord(body[p+1]); p := p + 2;
  extEnd := p + extsLen;
  while p + 4 <= extEnd do
  begin
    etype := (Ord(body[p]) shl 8) or Ord(body[p+1]);
    elen  := (Ord(body[p+2]) shl 8) or Ord(body[p+3]);
    p := p + 4;
    if etype = 51 then                        { key_share }
    begin
      group := (Ord(body[p]) shl 8) or Ord(body[p+1]);
      if group = $001d then                   { X25519 }
        serverKeyShare := Copy(body, p + 4, (Ord(body[p+2]) shl 8) or Ord(body[p+3]));
    end;
    p := p + elen;
  end;
  Result := (cipherSuite <> 0) and (Length(serverKeyShare) = 32);
end;

function TranscriptHash(const messages: AnsiString): AnsiString;
begin Result := Sha256(messages); end;

end.
