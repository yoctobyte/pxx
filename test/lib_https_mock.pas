program lib_https_mock;
{ End-to-end proof that http routes `https://` through the TLS seam
  (feature-tls-provider-abstraction + feature-own-net-http-lib). A mock plaintext
  backend (Read/Write just pass bytes over the fd, EAGAIN -> want-read/write so it
  works on the async reactor) is registered; the client fetches an `https://` URL
  with HttpGetAsync. The whole https client path runs: HttpParseUrl sees isTls,
  HttpTlsConnect handshakes through the seam, request/response go via
  TlsWrite/TlsRead. The server is plain (the mock is plaintext), so this tests the
  routing/plumbing end to end, no crypto. Also checks that with NO backend an
  https request fails cleanly (Ok=False), never crashes. }
uses scheduler, asyncnet, http, tls, sockets;

const PORT = 28760;

type
  TMockConn = record fd: cint; end;
  PMockConn = ^TMockConn;

  { Plaintext passthrough; async-aware (negative recv/send = would-block). }
  TMockTls = class(TTlsBackend)
    function  Name: string; override;
    function  Handshake(fd: Integer; role: TTlsRole; const host: string;
                        var c: TTlsConn): TTlsResult; override;
    function  Read (c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult; override;
    function  Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult; override;
    procedure Close(c: TTlsConn); override;
  end;

function TMockTls.Name: string;
begin Result := 'mock'; end;

function TMockTls.Handshake(fd: Integer; role: TTlsRole; const host: string;
                            var c: TTlsConn): TTlsResult;
var p: PMockConn;
begin
  GetMem(p, SizeOf(TMockConn));
  p^.fd := fd;
  c := p;
  Result := tlsOk;            { plaintext: handshake is a no-op }
end;

function TMockTls.Read(c: TTlsConn; buf: Pointer; len: Integer; var got: Integer): TTlsResult;
var n: Integer;
begin
  n := fpRecv(PMockConn(c)^.fd, buf, len, 0);
  if n > 0 then begin got := n; Result := tlsOk; end
  else if n = 0 then begin got := 0; Result := tlsClosed; end
  else begin got := 0; Result := tlsWantRead; end;   { EAGAIN on nonblocking fd }
end;

function TMockTls.Write(c: TTlsConn; buf: Pointer; len: Integer; var put: Integer): TTlsResult;
var n: Integer;
begin
  n := fpSend(PMockConn(c)^.fd, buf, len, 0);
  if n >= 0 then begin put := n; Result := tlsOk; end
  else begin put := 0; Result := tlsWantWrite; end;
end;

procedure TMockTls.Close(c: TTlsConn);
begin
  if c <> nil then FreeMem(c);
end;

var
  gStatus: Integer;
  gBody, gReason: AnsiString;
  gServerDone: Boolean;
  backend: TMockTls;
  noBackend: TTlsBackend;
  noBackResp: THttpResponse;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  lfd := TcpListen(PORT);
  cfd := TcpAccept(lfd);
  n := TcpRecv(cfd, @buf[0], 2048);
  resp := 'HTTP/1.1 200 OK'#13#10 +
          'Content-Length: 7'#13#10 +
          'Connection: close'#13#10#13#10 +
          'secured';
  TcpSend(cfd, @resp[1], Length(resp));
  TcpClose(cfd);
  TcpClose(lfd);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetAsync('https://127.0.0.1:28760/');   { isTls -> routed via the seam }
  gStatus := r.Status;
  gReason := r.Reason;
  gBody := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  { 1. No backend: an https request must fail cleanly, not crash. }
  noBackend := nil;
  TlsRegisterBackend(noBackend);
  noBackResp := HttpGet('https://127.0.0.1:1/');     { blocking path, no backend }
  SayBool('https-noback-clean', not noBackResp.Ok);

  { 2. Register the mock and fetch an https URL through the reactor. }
  backend := TMockTls.Create;
  TlsRegisterBackend(backend);
  SayBool('tls-available', TlsAvailable);

  gStatus := -1; gBody := ''; gReason := ''; gServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('https-status', gStatus = 200);
  SayBool('https-reason', gReason = 'OK');
  SayBool('https-body',   gBody = 'secured');

  TlsRegisterBackend(noBackend);
  backend.Free;
end.
