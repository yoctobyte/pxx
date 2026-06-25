program devtest_tls_openssl;
{ Dev-only: real HTTPS through the OpenSSL backend (feature-tls-provider-
  abstraction), incl. certificate verification + trust store. Build with
  -dPXX_DYNLIB_LIBC; driven by the `tls-openssl-devtest` Makefile target, which
  starts a loopback `openssl s_server` with a self-signed cert (CN/SAN=localhost)
  and passes <port> <cafile>.

  Proves four things against real OpenSSL:
    1. REJECT  — verify on, system trust store only: the self-signed server cert
                 is untrusted, so the handshake is refused (Ok=False).
    2. ACCEPT  — the test CA added to the store: handshake succeeds, GET -> 200.
    3. ASYNC   — same, but HttpGetAsync on the reactor (non-blocking handshake).
    4. (the hostname is matched: we connect to https://localhost and the cert is
        for localhost).

  Usage: devtest_tls_openssl <port> <cafile> }
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

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  port, caFile: AnsiString;
  r: THttpResponse;
  rejectOk, acceptOk, asyncOk: Boolean;
begin
  if ParamCount >= 1 then port := ParamStr(1) else port := '28770';
  if ParamCount >= 2 then caFile := ParamStr(2) else caFile := '';
  gUrl := 'https://localhost:' + port + '/';

  { 1. REJECT: verify on, do NOT trust the test CA. }
  if not OpenSslTlsRegisterEx(True, '') then
  begin writeln('register=FAIL (no loader / libssl?)'); writeln('FAIL'); Halt(1); end;
  r := HttpGet(gUrl);
  rejectOk := not r.Ok;
  writeln('reject: ok=', r.Ok, ' verify_result=', OpenSslTlsLastVerifyResult);
  SayBool('reject-untrusted', rejectOk);
  OpenSslTlsUnregister;

  { 2. ACCEPT: trust the test CA -> verification + hostname match pass. }
  if not OpenSslTlsRegisterEx(True, caFile) then
  begin writeln('register-ca=FAIL'); writeln('FAIL'); Halt(1); end;
  r := HttpGet(gUrl);
  acceptOk := r.Ok and (r.Status = 200) and (Length(r.Body) > 0);
  writeln('accept: status=', r.Status, ' bodylen=', Length(r.Body));
  SayBool('accept-trusted', acceptOk);

  { 3. ASYNC over the verified connection. }
  gAsyncStatus := -1; gAsyncBodyLen := 0;
  Spawn(@AsyncCo, nil);
  RunUntilDone;
  asyncOk := (gAsyncStatus = 200) and (gAsyncBodyLen > 0);
  writeln('async: status=', gAsyncStatus, ' bodylen=', gAsyncBodyLen);
  SayBool('async-trusted', asyncOk);

  OpenSslTlsUnregister;

  if rejectOk and acceptOk and asyncOk then writeln('ALL OK') else writeln('FAIL');
end.
