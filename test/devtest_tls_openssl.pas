program devtest_tls_openssl;
{ Dev-only: real HTTPS GET through the OpenSSL backend (feature-tls-provider-
  abstraction). Build with -dPXX_DYNLIB_LIBC (needs the dlopen loader) against a
  loopback `openssl s_server -www`. Not in the hermetic lib-test gate — driven by
  the `tls-openssl-devtest` Makefile target, which provides the server + cert.

  Usage: devtest_tls_openssl <url> }
uses sysutils, http, tls_openssl;
var r: THttpResponse; url: AnsiString;
begin
  if ParamCount >= 1 then url := ParamStr(1)
  else url := 'https://127.0.0.1:28770/';

  if not OpenSslTlsRegister then
  begin
    writeln('register=FAIL (no loader / libssl?)');
    writeln('FAIL');
    Halt(1);
  end;
  writeln('register=ok backend=', TlsActiveBackend.Name);

  r := HttpGet(url);
  writeln('status=', r.Status);
  writeln('ok=', r.Ok);
  writeln('bodylen=', Length(r.Body));

  if (r.Status = 200) and (Length(r.Body) > 0) then writeln('ALL OK')
  else writeln('FAIL');

  OpenSslTlsUnregister;
end.
