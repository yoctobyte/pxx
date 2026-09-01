program devtest_https_native_async;
{ https:// over the ASYNC reactor path, onto the native TLS 1.3 backend.

  THE SYNC TWIN IS NOT A SUBSTITUTE FOR THIS, and that is the whole reason the
  file exists. The async path hands the TLS handshake a NON-BLOCKING fd
  (TcpConnectAddr calls PalSetSocketNonBlocking), so it exercises code the
  blocking devtest cannot reach. Until 2026-09-01 the backend read EAGAIN as
  end-of-stream and every async https request failed -- reporting
  `no ServerHello (connection closed)` about a connection that was open and
  healthy -- while devtest_https_native passed against the same server.

  It runs on a PLAIN Spawn, not SpawnSized, deliberately: the default
  coroutine stack must be large enough for a handshake (X.509 parse, signature
  verify, trust-store walk). At the old 64 KB default this segfaulted with no
  output at all.

  Usage: devtest_https_native_async <url>
  Trust anchors from SSL_CERT_FILE when set, else the system bundle.
  Driven by tools/tls_native_seam_devtest.sh; non-hermetic (needs openssl). }
uses sysutils, http, tls, tls13_native, scheduler;

var
  gUrl: AnsiString;
  gStatus: Integer;
  gErr: AnsiString;

procedure Body(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpRequestAsync('GET', gUrl, '', '');
  gStatus := r.Status;
  if not r.Ok then gErr := Tls13NativeLastError;
end;

begin
  Tls13NativeRegister;
  gUrl := ParamStr(1);
  gStatus := 0; gErr := '';
  WriteLn('backend=', TlsActiveBackend.Name);
  Spawn(@Body, nil);
  RunUntilDone;
  WriteLn('status=', gStatus);
  if gStatus = 200 then WriteLn('ASYNC HTTPS OK')
  else WriteLn('ASYNC HTTPS FAIL: ', gErr);
end.
