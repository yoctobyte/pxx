program lib_tls13_hs;
{ TLS 1.3 handshake messages: ClientHello builder framing + ServerHello parser. }
uses tls13_hs, sha256;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function U16(v: Integer): AnsiString;
begin U16 := Chr((v shr 8) and $ff) + Chr(v and $ff); end;

function V16(const s: AnsiString): AnsiString;
begin V16 := U16(Length(s)) + s; end;

function Rep(b, n: Integer): AnsiString;
var i: Integer;
begin Rep := ''; for i := 1 to n do Rep := Rep + Chr(b); end;

var
  ch, body, sh, shExts, sks, rnd, pub, srv: AnsiString;
  mt: Byte; np, cs: Integer;
begin
  rnd := Rep(0, 32); pub := Rep($aa, 32); srv := Rep($bb, 32);

  { ClientHello frames correctly (type=1, declared length spans the message) }
  ch := BuildClientHello(rnd, pub, 'example.com');
  HsRead(ch, 1, mt, body, np);
  SayBool('clienthello-frame', (mt = HS_CLIENT_HELLO) and (np = Length(ch) + 1));
  SayBool('clienthello-nonempty', Length(body) > 60);

  { ServerHello parse: extract cipher suite + X25519 key_share }
  shExts := U16(51) + V16(U16($001d) + V16(srv))      { key_share X25519 }
          + U16(43) + V16(U16($0304));                { supported_versions = 1.3 }
  sh := U16($0303) + rnd + Chr(0) + U16($1301) + Chr(0) + V16(shExts);
  SayBool('serverhello-parse', ParseServerHello(sh, cs, sks));
  SayBool('serverhello-cipher', cs = CS_AES_128_GCM_SHA256);
  SayBool('serverhello-keyshare', sks = srv);

  { transcript hash = SHA-256 over the concatenated messages }
  SayBool('transcript-hash', TranscriptHash('abc') = Sha256('abc'));
end.
