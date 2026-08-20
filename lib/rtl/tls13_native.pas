{ SPDX-License-Identifier: Zlib }
unit tls13_native;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The NATIVE TLS 1.3 backend behind the tls.pas seam — syscall-only, no libssl,
  no libc (feature-tls-provider-abstraction slice 2, over
  feature-tls13-from-scratch).

  Until this unit existed the from-scratch client worked but could not be
  CALLED: its handshake lived in test/devtest_tls13_handshake.pas, so an
  https:// caller's only option was the OpenSSL backend and its dlopen. This is
  the same handshake, behind TTlsBackend.

  WHAT IT DOES
    ClientHello -> ServerHello -> X25519 ECDHE -> handshake key schedule ->
    decrypt the server flight -> verify CertificateVerify -> verify the server
    Finished -> verify the certificate chain against the SYSTEM TRUST STORE ->
    send client Finished -> application keys -> record I/O.

  Two properties are load-bearing and are stated here because they are the kind
  a later refactor quietly drops:

  1. CertificateVerify FAILS CLOSED. Every signature scheme the ClientHello
     offers must be verifiable, and a scheme we cannot check is a hard error.
     It is not a warning: until 2026-08-01 the devtest skipped verification for
     three of the four schemes it advertised, which let a server complete the
     handshake without ever proving it held its certificate's private key.
  2. The chain is verified against the system trust store via
     truststore.VerifyServerChain — leaf plus intermediates in any order,
     walked to a root the store holds — not against a CA handed in by the
     caller. A client that validates a chain but anchors it nowhere establishes
     nothing.

  LIMITS, stated rather than discovered
    * The handshake is BLOCKING. The seam permits this ("a backend over a
      blocking fd simply returns tlsOk/tlsError and never wants"), and
      HandshakeResume is correspondingly a no-op. Driving it from the async
      reactor needs a real state machine; that is a separate slice, and faking
      want-read/want-write here would be a lie the reactor would trip over.
    * Client role only. TlsServer returns tlsError.
    * X25519 + AES-128-GCM / ChaCha20-Poly1305, matching what BuildClientHello
      offers. No HelloRetryRequest, no session resumption.
    * kTLS TX offload is used when available (AES-GCM only), exactly as the
      devtest does; RX always runs the Pascal record layer, so the server's
      NewSessionTicket control records need no recvmsg. }

interface

uses tls;

type
  TTls13Native = class(TTlsBackend)
    function  Name: string; override;
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; override;
    function  HandshakeResume(c: TTlsConn): TTlsResult; override;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; override;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; override;
    procedure Close(c: TTlsConn); override;
  end;

{ Why the last handshake failed, for callers and tests. The seam reports only
  tlsError; a TLS failure has many distinct causes and "it didn't work" is not
  a diagnosis. Empty when the last handshake succeeded. }
function Tls13NativeLastError: AnsiString;

{ Install this backend as the process-global default.

  EXPLICIT on purpose, and NOT called from this unit's initialization. Merely
  linking a unit must not change which TLS stack a program trusts: that is a
  process-global, and a link-order artifact is the wrong way to decide it. It
  also matches the only other backend — tls_openssl registers only when
  OpenSslTlsRegisterEx is called — so "who is the backend" is always something
  a caller decided, and calling one after the other is a deterministic override
  rather than a race between two initialization sections. }
procedure Tls13NativeRegister;

implementation

uses sysutils, net, platform, random, x25519, sha256, tls13_keys, tls13_record,
     tls13_hs, x509, truststore, ed25519, ecdsa_p256, rsa, tls13_ktls;

const
  MAX_CERTS = 10;         { matches truststore.MAX_CHAIN }

type
  TNativeConn = class
    Fd:       Integer;
    Suite:    Integer;
    CKey, CIv: AnsiString;    { client application traffic }
    SKey, SIv: AnsiString;    { server application traffic }
    SeqC, SeqS: Int64;
    RxPlain:  AnsiString;     { decrypted application bytes not yet delivered }
    KtlsTx:   Boolean;
    Dead:     Boolean;        { peer closed or a fatal record error }
  end;

var
  gLastError: AnsiString;
  gBackend: TTls13Native;

function Tls13NativeLastError: AnsiString;
begin
  Tls13NativeLastError := gLastError;
end;

function Fail(const why: AnsiString): TTlsResult;
begin
  gLastError := why;
  Fail := tlsError;
end;

function TTls13Native.Name: string;
begin
  Name := 'native-tls13';
end;

{ ---- socket helpers (blocking) -------------------------------------------- }

function RecvN(fd: Integer; n: Integer; var out_: AnsiString): Boolean;
var got: Int64; buf: array[0..4095] of Byte; need, chunk, k: Integer;
begin
  out_ := ''; need := n;
  while need > 0 do
  begin
    chunk := need; if chunk > 4096 then chunk := 4096;
    got := NetRecv(fd, @buf[0], chunk);
    if got <= 0 then begin RecvN := False; Exit; end;
    for k := 0 to Integer(got) - 1 do out_ := out_ + Chr(buf[k]);
    need := need - Integer(got);
  end;
  RecvN := True;
end;

function ReadRecord(fd: Integer; var ctype: Byte; var payload: AnsiString): Boolean;
var hdr: AnsiString; len: Integer;
begin
  ReadRecord := False;
  if not RecvN(fd, 5, hdr) then Exit;
  if Length(hdr) <> 5 then Exit;
  ctype := Ord(hdr[1]);
  len := (Ord(hdr[4]) shl 8) or Ord(hdr[5]);
  if len = 0 then begin payload := ''; ReadRecord := True; Exit; end;
  if not RecvN(fd, len, payload) then Exit;
  ReadRecord := Length(payload) = len;
end;

procedure SendBytes(fd: Integer; const s: AnsiString);
begin
  if s <> '' then NetSend(fd, @s[1], Length(s));
end;

function RecHdr(ctype, len: Integer): AnsiString;
begin
  RecHdr := Chr(ctype) + Chr($03) + Chr($03) +
            Chr((len shr 8) and $ff) + Chr(len and $ff);
end;

function FinishedKey(const secret: AnsiString): AnsiString;
begin
  FinishedKey := HkdfExpandLabel(secret, 'finished', '', 32);
end;

function HexOf(const r: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  HexOf := '';
  for i := 1 to Length(r) do
  begin b := Ord(r[i]); HexOf := HexOf + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

{ Current UTC as X.509's YYYYMMDDHHMMSS. Now is built on PalRealtime, which is
  UTC, so no timezone adjustment applies. }
function UtcNowStr: AnsiString;
begin
  UtcNowStr := FormatDateTime('yyyymmddhhnnss', Now);
end;

{ ---- handshake ------------------------------------------------------------ }

function TTls13Native.Handshake(fd: Integer; role: TTlsRole; const host: string;
                                var c: TTlsConn): TTlsResult;
var
  conn: TNativeConn;
  priv, pub, clientRandom, chMsg, transcript: AnsiString;
  ctype: Byte; payload, shBody: AnsiString;
  cipher, suite, i: Integer;
  serverKeyShare, ecdhe: AnsiString;
  es, hsSec, ms, hsHash: AnsiString;
  sHs, cHs, sKey, sIv, cKey, cIv: AnsiString;
  srvBuf: AnsiString; parsePos: Integer;
  mt: Byte; body: AnsiString; np: Integer; sawFinished: Boolean;
  seqS, seqC: Int64;
  rec, ptext: AnsiString; rct: Byte;
  sFinKey, cFinKey, expectFin, cFinData, cFinMsg, cFinRec: AnsiString;
  cApp, sApp, cAppKey, cAppIv, sAppKey, sAppIv: AnsiString;
  leaf: TCert; certVerifyHash, signedContent, cvScheme, cvSig: AnsiString;
  cvRS, cvN, cvE: AnsiString; cvOk: Boolean;
  cp, ctxLen, certLen, sl, listEnd: Integer;
  certList: array[0..MAX_CERTS - 1] of AnsiString;
  certCount: Integer;
  store: TTrustStore;
  rndBuf: array[0..63] of Byte;

  function AeadSuite: Integer;
  begin
    if suite = CS_CHACHA20_POLY1305 then AeadSuite := TLS_CHACHA20_POLY1305
    else AeadSuite := TLS_AES_128_GCM;
  end;

  procedure DeriveTraffic(const secret: AnsiString; var key, iv: AnsiString);
  begin
    if suite = CS_CHACHA20_POLY1305 then key := TrafficKey(secret, 32)
    else key := TrafficKey(secret, 16);
    iv := TrafficIv(secret);
  end;

begin
  c := nil;
  gLastError := '';
  if role <> tlsClient then
  begin
    Handshake := Fail('native TLS 1.3: server role is not implemented');
    Exit;
  end;

  { The ephemeral X25519 private key and the client random. Both MUST be
    unpredictable: the devtest used FIXED bytes (1..32 and 101..132), which is
    fine for a loopback test and would be a catastrophe here — a predictable
    private key hands the session to anyone who guesses it.

    From the OS CSPRNG (getrandom(2), /dev/urandom fallback), and a failure to
    get entropy is FATAL rather than silently falling back to a PRNG: a
    handshake with guessable key material is worse than no handshake. }
  if not OSEntropyBytes(@rndBuf[0], 64) then
  begin
    Handshake := Fail('no OS entropy available for the ephemeral key');
    Exit;
  end;
  priv := '';
  for i := 0 to 31 do priv := priv + Chr(rndBuf[i]);
  clientRandom := '';
  for i := 32 to 63 do clientRandom := clientRandom + Chr(rndBuf[i]);
  pub := X25519Base(priv);

  chMsg := BuildClientHello(clientRandom, pub, host);
  SendBytes(fd, RecHdr(22, Length(chMsg)) + chMsg);
  transcript := chMsg;

  { ServerHello (a middlebox-compat change_cipher_spec may precede it) }
  if not ReadRecord(fd, ctype, payload) then
  begin Handshake := Fail('no ServerHello (connection closed)'); Exit; end;
  while ctype = 20 do
    if not ReadRecord(fd, ctype, payload) then
    begin Handshake := Fail('no ServerHello after CCS'); Exit; end;
  if ctype <> 22 then
  begin Handshake := Fail('expected a handshake record, got type ' + IntToStr(ctype)); Exit; end;
  HsRead(payload, 1, mt, shBody, np);
  if mt <> HS_SERVER_HELLO then
  begin Handshake := Fail('expected ServerHello, got handshake type ' + IntToStr(mt)); Exit; end;
  if not ParseServerHello(shBody, cipher, serverKeyShare) then
  begin Handshake := Fail('malformed ServerHello'); Exit; end;
  suite := cipher;
  transcript := transcript + payload;

  { ECDHE + the handshake key schedule }
  ecdhe := X25519(priv, serverKeyShare);
  es := EarlySecret('');
  hsSec := HandshakeSecret(es, ecdhe);
  hsHash := TranscriptHash(transcript);              { CH..SH }
  sHs := DeriveSecret(hsSec, 's hs traffic', hsHash);
  cHs := DeriveSecret(hsSec, 'c hs traffic', hsHash);
  DeriveTraffic(sHs, sKey, sIv);
  DeriveTraffic(cHs, cKey, cIv);

  { the server flight, decrypted with the handshake keys, until Finished }
  srvBuf := ''; parsePos := 1; sawFinished := False; seqS := 0;
  certCount := 0;
  sFinKey := FinishedKey(sHs);
  while not sawFinished do
  begin
    if not ReadRecord(fd, ctype, payload) then
    begin Handshake := Fail('connection closed during the server flight'); Exit; end;
    if ctype = 20 then Continue;                     { CCS }
    if ctype <> 23 then
    begin Handshake := Fail('unexpected record type in the server flight'); Exit; end;
    rec := RecHdr(23, Length(payload)) + payload;
    if not Tls13Open(AeadSuite, sKey, sIv, seqS, rec, ptext, rct) then
    begin Handshake := Fail('failed to decrypt the server flight'); Exit; end;
    seqS := seqS + 1;
    if rct <> 22 then Continue;
    srvBuf := srvBuf + ptext;
    while parsePos + 4 <= Length(srvBuf) + 1 do
    begin
      np := (Ord(srvBuf[parsePos+1]) shl 16) or (Ord(srvBuf[parsePos+2]) shl 8)
            or Ord(srvBuf[parsePos+3]);
      if parsePos + 4 + np > Length(srvBuf) + 1 then Break;   { incomplete }
      mt := Ord(srvBuf[parsePos]);
      body := Copy(srvBuf, parsePos, 4 + np);
      if mt = HS_FINISHED then
      begin
        expectFin := HmacSha256(sFinKey, TranscriptHash(transcript));
        if Copy(srvBuf, parsePos + 4, np) <> expectFin then
        begin Handshake := Fail('server Finished MAC mismatch'); Exit; end;
        transcript := transcript + body;
        sawFinished := True;
        Break;
      end
      else
      begin
        if mt = HS_CERTIFICATE then
        begin
          { Certificate = ctx(1+len) || cert_list(3) || [ cert(3+DER) ext(2) ]...
            The devtest read only the LEAF; the whole list is collected here so
            the chain can be walked to a root through any intermediates. }
          cp := 5;
          ctxLen := Ord(body[cp]); cp := cp + 1 + ctxLen;
          listEnd := cp + 3 +
                     ((Ord(body[cp]) shl 16) or (Ord(body[cp+1]) shl 8) or Ord(body[cp+2]));
          cp := cp + 3;
          while (cp + 2 <= Length(body)) and (cp < listEnd) and (certCount < MAX_CERTS) do
          begin
            certLen := (Ord(body[cp]) shl 16) or (Ord(body[cp+1]) shl 8) or Ord(body[cp+2]);
            cp := cp + 3;
            if (certLen <= 0) or (cp + certLen - 1 > Length(body)) then Break;
            certList[certCount] := Copy(body, cp, certLen);
            certCount := certCount + 1;
            cp := cp + certLen;
            if cp + 1 > Length(body) then Break;
            cp := cp + 2 + ((Ord(body[cp]) shl 8) or Ord(body[cp+1]));  { extensions }
          end;
          if certCount = 0 then
          begin Handshake := Fail('server sent an empty certificate_list'); Exit; end;
          leaf := X509Parse(certList[0]);
          if not leaf.Ok then
          begin Handshake := Fail('leaf certificate did not parse'); Exit; end;
        end;
        transcript := transcript + body;
        if mt = HS_CERTIFICATE then certVerifyHash := TranscriptHash(transcript);
        if mt = HS_CERTIFICATE_VERIFY then
        begin
          { body: type(1)+len(3) then scheme(2) + sig(2-byte len + sig) }
          cvScheme := Copy(body, 5, 2);
          sl := (Ord(body[7]) shl 8) or Ord(body[8]);
          cvSig := Copy(body, 9, sl);
          signedContent := '';
          for cp := 1 to 64 do signedContent := signedContent + Chr($20);
          signedContent := signedContent + 'TLS 1.3, server CertificateVerify' +
                           Chr(0) + certVerifyHash;
          { FAIL CLOSED. See the unit header: a scheme we cannot verify is an
            error, never a skip. rsa_pkcs1_sha256 (0401) is rejected on purpose
            — RFC 8446 4.4.3 allows the codepoint in signature_algorithms
            (it describes CERTIFICATE signatures) but forbids it here. }
          cvOk := False;
          if (Ord(cvScheme[1]) = $08) and (Ord(cvScheme[2]) = $07) then       { ed25519 }
            cvOk := Ed25519Verify(leaf.PubBits, signedContent, cvSig)
          else if (Ord(cvScheme[1]) = $04) and (Ord(cvScheme[2]) = $03) then  { ecdsa_p256 }
          begin
            EcdsaRS(cvSig, cvRS);
            cvOk := EcdsaP256Verify(Copy(leaf.PubBits, 2, 64), signedContent, cvRS);
          end
          else if (Ord(cvScheme[1]) = $08) and (Ord(cvScheme[2]) = $04) then  { rsa_pss }
          begin
            RsaKey(leaf.PubBits, cvN, cvE);
            cvOk := RsaVerifyPssSha256(cvN, cvE, signedContent, cvSig);
          end
          else
          begin
            Handshake := Fail('CertificateVerify scheme ' + HexOf(cvScheme) +
                              ' is not one this client can verify');
            Exit;
          end;
          if not cvOk then
          begin Handshake := Fail('CertificateVerify signature is invalid'); Exit; end;
        end;
      end;
      parsePos := parsePos + 4 + np;
    end;
  end;

  { The chain, anchored in the SYSTEM trust store. CertificateVerify proved the
    peer holds the leaf's key; this proves the leaf is one we should trust. }
  if not LoadSystemTrust(store) then
  begin Handshake := Fail('no system trust store could be read'); Exit; end;
  if store.Count = 0 then
  begin Handshake := Fail('system trust store is empty (trusts nothing)'); Exit; end;
  if not VerifyServerChain(store, certList, certCount, UtcNowStr, host) then
  begin
    Handshake := Fail('certificate chain does not verify to a trusted root ' +
                      '(store ' + store.Source + ', ' + IntToStr(store.Count) + ' roots)');
    Exit;
  end;

  { client Finished over CH..server-Finished, then the application keys }
  cFinKey := FinishedKey(cHs);
  cFinData := HmacSha256(cFinKey, TranscriptHash(transcript));
  cFinMsg := HsWrap(HS_FINISHED, cFinData);

  ms := MasterSecret(hsSec);
  hsHash := TranscriptHash(transcript);
  cApp := DeriveSecret(ms, 'c ap traffic', hsHash);
  sApp := DeriveSecret(ms, 's ap traffic', hsHash);
  DeriveTraffic(cApp, cAppKey, cAppIv);
  DeriveTraffic(sApp, sAppKey, sAppIv);

  SendBytes(fd, RecHdr(20, 1) + Chr(1));             { middlebox-compat CCS }
  seqC := 0;
  cFinRec := Tls13Seal(AeadSuite, cKey, cIv, seqC, CT_HANDSHAKE, cFinMsg);
  SendBytes(fd, cFinRec);

  conn := TNativeConn.Create;
  conn.Fd := fd;
  conn.Suite := suite;
  conn.CKey := cAppKey; conn.CIv := cAppIv;
  conn.SKey := sAppKey; conn.SIv := sAppIv;
  conn.SeqC := 0; conn.SeqS := 0;
  conn.RxPlain := '';
  conn.Dead := False;

  { kTLS TX offload: the kernel seals our application writes. AES-GCM only, and
    TX only — RX stays on the Pascal record layer so the server's
    NewSessionTicket control records need no recvmsg. }
  conn.KtlsTx := (suite = CS_AES_128_GCM_SHA256)
                 and KtlsEnable(fd)
                 and KtlsSetAesGcm128(fd, True, cAppKey, cAppIv);

  c := TTlsConn(conn);
  Handshake := tlsOk;
end;

function TTls13Native.HandshakeResume(c: TTlsConn): TTlsResult;
begin
  { The handshake above is blocking and completes in one call, so there is
    nothing to resume. The seam explicitly allows this; a caller written to the
    want-read/want-write contract still works, it simply never sees a want. }
  if c = nil then HandshakeResume := tlsError else HandshakeResume := tlsOk;
end;

{ ---- record I/O ----------------------------------------------------------- }

function TTls13Native.Read(c: TTlsConn; buf: Pointer; len: Integer;
                           var got: Integer): TTlsResult;
var
  conn: TNativeConn;
  ctype: Byte; payload, rec, ptext: AnsiString; rct: Byte;
  n, i: Integer;
  p: ^Byte;
  aead: Integer;
begin
  got := 0;
  if (c = nil) or (buf = nil) or (len <= 0) then begin Read := tlsError; Exit; end;
  conn := TNativeConn(c);

  { Serve from the leftover plaintext first: one TLS record can carry more than
    the caller's buffer, and dropping the remainder would silently lose data. }
  while conn.RxPlain = '' do
  begin
    if conn.Dead then begin Read := tlsClosed; Exit; end;
    if not ReadRecord(conn.Fd, ctype, payload) then
    begin conn.Dead := True; Read := tlsClosed; Exit; end;
    if ctype = 20 then Continue;                     { CCS: ignore }
    if ctype <> 23 then begin conn.Dead := True; Read := tlsError; Exit; end;
    rec := RecHdr(23, Length(payload)) + payload;
    if conn.Suite = CS_CHACHA20_POLY1305 then aead := TLS_CHACHA20_POLY1305
    else aead := TLS_AES_128_GCM;
    if not Tls13Open(aead, conn.SKey, conn.SIv, conn.SeqS, rec, ptext, rct) then
    begin
      { A record we cannot open is fatal: it may be a post-handshake message we
        do not implement, but continuing would desynchronise the sequence
        number and every later record would fail too. }
      conn.Dead := True;
      gLastError := 'could not decrypt an application record';
      Read := tlsError;
      Exit;
    end;
    conn.SeqS := conn.SeqS + 1;
    if rct = 21 then begin conn.Dead := True; Read := tlsClosed; Exit; end;  { alert }
    if rct = 23 then conn.RxPlain := conn.RxPlain + ptext;
    { rct = 22 is a post-handshake message (NewSessionTicket): consume it }
  end;

  n := Length(conn.RxPlain);
  if n > len then n := len;
  p := buf;
  for i := 1 to n do
  begin
    p^ := Ord(conn.RxPlain[i]);
    p := Pointer(Int64(p) + 1);
  end;
  conn.RxPlain := Copy(conn.RxPlain, n + 1, Length(conn.RxPlain) - n);
  got := n;
  Read := tlsOk;
end;

function TTls13Native.Write(c: TTlsConn; buf: Pointer; len: Integer;
                            var put: Integer): TTlsResult;
var
  conn: TNativeConn;
  s, rec: AnsiString;
  i, aead: Integer;
  p: ^Byte;
begin
  put := 0;
  if (c = nil) or (buf = nil) or (len <= 0) then begin Write := tlsError; Exit; end;
  conn := TNativeConn(c);
  if conn.Dead then begin Write := tlsClosed; Exit; end;

  s := '';
  p := buf;
  for i := 1 to len do
  begin
    s := s + Chr(p^);
    p := Pointer(Int64(p) + 1);
  end;

  if conn.KtlsTx then
    SendBytes(conn.Fd, s)                            { the kernel seals it }
  else
  begin
    if conn.Suite = CS_CHACHA20_POLY1305 then aead := TLS_CHACHA20_POLY1305
    else aead := TLS_AES_128_GCM;
    rec := Tls13Seal(aead, conn.CKey, conn.CIv, conn.SeqC, CT_APPLICATION_DATA, s);
    conn.SeqC := conn.SeqC + 1;
    SendBytes(conn.Fd, rec);
  end;
  put := len;
  Write := tlsOk;
end;

procedure TTls13Native.Close(c: TTlsConn);
var conn: TNativeConn;
begin
  { Releases the TLS layer, not the fd — the seam's contract. }
  if c = nil then Exit;
  conn := TNativeConn(c);
  conn.Dead := True;
  conn.Free;
end;

procedure Tls13NativeRegister;
begin
  if gBackend = nil then gBackend := TTls13Native.Create;
  TlsRegisterBackend(gBackend);
end;

initialization
  gLastError := '';
  gBackend := nil;
  { deliberately NOT registering here — see Tls13NativeRegister }
end.
