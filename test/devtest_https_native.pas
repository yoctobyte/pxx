program devtest_https_native;
{ The chain end to end: HttpGet over https:// through the tls.pas seam onto the
  native TLS 1.3 backend — no libssl, no dlopen, no OpenSSL in the process.

  This is the outcome feature-tls13-from-scratch and
  feature-tls-provider-abstraction exist for. Until tls13_native shipped, an
  https:// URL here failed cleanly for want of a backend; the only alternative
  was the OpenSSL backend, which needs the real dynamic loader.

  Usage: devtest_https_native <url>
  Trust anchors come from SSL_CERT_FILE when set, else the system bundle.
  Driven by tools/tls_native_seam_devtest.sh; non-hermetic (needs openssl). }
uses sysutils, http, tls, tls13_native;
var r: THttpResponse;
begin
  Tls13NativeRegister;
  WriteLn('backend=', TlsActiveBackend.Name);
  r := HttpGet(ParamStr(1));
  WriteLn('status=', r.Status, ' reason=', r.Reason);
  WriteLn('bodyhead=', Copy(r.Body, 1, 24));
  if r.Status = 200 then WriteLn('HTTPS OK') else WriteLn('HTTPS FAIL: ', Tls13NativeLastError);
end.
