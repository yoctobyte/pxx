program devtest_tls_openssl;
{ Dev-only: real HTTPS GET through the OpenSSL backend (feature-tls-provider-
  abstraction). Build with -dPXX_DYNLIB_LIBC (needs the dlopen loader) against a
  loopback `openssl s_server -www`. Not in the hermetic lib-test gate — driven by
  the `tls-openssl-devtest` Makefile target, which provides the server + cert.

  Exercises BOTH transports over real TLS:
    * blocking  HttpGet      (SSL_connect completes in one step on a blocking fd)
    * async     HttpGetAsync (non-blocking fd: handshake yields on want-read/write
                              via the reactor and resumes — the async TLS path)

  Usage: devtest_tls_openssl <url> }
uses sysutils, scheduler, http, tls_openssl;

var
  gUrl: AnsiString;
  gAsyncStatus, gAsyncBodyLen: Integer;

procedure AsyncCo(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetAsync(gUrl);
  gAsyncStatus := r.Status;
  gAsyncBodyLen := Length(r.Body);
end;

var
  r: THttpResponse;
  blkOk, asyncOk: Boolean;
begin
  if ParamCount >= 1 then gUrl := ParamStr(1)
  else gUrl := 'https://127.0.0.1:28770/';

  if not OpenSslTlsRegister then
  begin
    writeln('register=FAIL (no loader / libssl?)');
    writeln('FAIL');
    Halt(1);
  end;
  writeln('register=ok backend=', TlsActiveBackend.Name);

  { 1. blocking }
  r := HttpGet(gUrl);
  writeln('blocking: status=', r.Status, ' bodylen=', Length(r.Body));
  blkOk := (r.Status = 200) and (Length(r.Body) > 0);

  { 2. async (reactor-driven handshake + GET) }
  gAsyncStatus := -1; gAsyncBodyLen := 0;
  Spawn(@AsyncCo, nil);
  RunUntilDone;
  writeln('async:    status=', gAsyncStatus, ' bodylen=', gAsyncBodyLen);
  asyncOk := (gAsyncStatus = 200) and (gAsyncBodyLen > 0);

  if blkOk and asyncOk then writeln('ALL OK') else writeln('FAIL');

  OpenSslTlsUnregister;
end.
