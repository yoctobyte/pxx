program devtest_tls_interop;
{ Dev-only TLS interop: OUR OpenSSL-backed HTTPS *server* (SSL_accept via the
  seam) <-> OUR HttpGetAsync *client*, both as coroutines on one reactor thread,
  over real OpenSSL. Proves the seam's server role and that a single process can
  serve and consume TLS at once. The client verifies the server cert (the test
  cert is trusted as a CA) and matches the hostname (localhost).

  Build with -dPXX_DYNLIB_LIBC. Driven by tls-openssl-devtest.
  Usage: devtest_tls_interop <port> <certfile> <keyfile> }
uses sysutils, scheduler, asyncnet, tls, http, tls_openssl;

var
  gPort: Integer;
  gCert, gKey: AnsiString;
  gServerDone: Boolean;
  gClientStatus, gClientBodyLen: Integer;

{ Drive a handshake to completion on the reactor (yield on want). }
function DriveHandshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): Boolean;
var r: TTlsResult;
begin
  r := TlsHandshake(fd, role, host, c);
  while (r = tlsWantRead) or (r = tlsWantWrite) do
  begin
    if r = tlsWantRead then WaitReadable(fd) else WaitWritable(fd);
    r := TlsHandshakeResume(c);
  end;
  Result := r = tlsOk;
  if not Result and (c <> nil) then begin TlsClose(c); c := nil; end;
end;

function TlsRecvSome(fd: Integer; c: TTlsConn; buf: Pointer; len: Integer): Integer;
var got: Integer; r: TTlsResult;
begin
  repeat
    r := TlsRead(c, buf, len, got);
    if r = tlsWantRead then WaitReadable(fd)
    else if r = tlsWantWrite then WaitWritable(fd);
  until (r <> tlsWantRead) and (r <> tlsWantWrite);
  if r = tlsOk then Result := got
  else if r = tlsClosed then Result := 0
  else Result := -1;
end;

function TlsSendAll(fd: Integer; c: TTlsConn; buf: Pointer; len: Integer): Boolean;
var off, put: Integer; r: TTlsResult;
begin
  off := 0;
  while off < len do
  begin
    r := TlsWrite(c, Pointer(Int64(buf) + off), len - off, put);
    if r = tlsOk then off := off + put
    else if r = tlsWantWrite then WaitWritable(fd)
    else if r = tlsWantRead then WaitReadable(fd)
    else begin Result := False; Exit; end;
  end;
  Result := True;
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd, n: Integer; sc: TTlsConn; buf: array[0..2047] of Byte; resp: AnsiString;
begin
  lfd := TcpListen(gPort);
  cfd := TcpAccept(lfd);                 { yields until the client connects }
  if DriveHandshake(cfd, tlsServer, '', sc) then
  begin
    n := TlsRecvSome(cfd, sc, @buf[0], 2048);     { read the request }
    if n > 0 then
    begin
      resp := 'HTTP/1.1 200 OK'#13#10 +
              'Content-Length: 9'#13#10 +
              'Connection: close'#13#10#13#10 +
              'pxx-tls!!';
      TlsSendAll(cfd, sc, @resp[1], Length(resp));
    end;
    TlsClose(sc);
  end;
  TcpClose(cfd);
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetAsync('https://localhost:' + IntToStr(gPort) + '/');
  gClientStatus := r.Status;
  gClientBodyLen := Length(r.Body);
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  if ParamCount < 3 then begin writeln('usage: devtest_tls_interop <port> <cert> <key>'); Halt(2); end;
  gPort := StrToInt(ParamStr(1));
  gCert := ParamStr(2);
  gKey  := ParamStr(3);

  if not OpenSslTlsServerInit(gCert, gKey) then
  begin writeln('server-init=FAIL'); writeln('FAIL'); Halt(1); end;
  if not OpenSslTlsRegisterEx(True, gCert) then         { client trusts the test cert }
  begin writeln('client-register=FAIL'); writeln('FAIL'); Halt(1); end;

  gServerDone := False; gClientStatus := -1; gClientBodyLen := 0;
  Spawn(@ServerCo, nil);                  { listen first }
  Spawn(@ClientCo, nil);
  RunUntilDone;                           { reactor drives both handshakes + I/O }

  SayBool('server-done', gServerDone);
  writeln('client: status=', gClientStatus, ' bodylen=', gClientBodyLen);
  SayBool('client-verified-200', (gClientStatus = 200) and (gClientBodyLen = 9));

  if gServerDone and (gClientStatus = 200) and (gClientBodyLen = 9) then writeln('ALL OK')
  else writeln('FAIL');

  OpenSslTlsUnregister;
end.
