program devtest_tls_native_seam;
{ The native TLS 1.3 backend driven PURELY through the tls.pas seam
  (feature-tls-provider-abstraction slice 2).

  No tls13_* call appears below -- only TlsHandshake / TlsWrite / TlsRead /
  TlsClose. That is the whole point: before tls13_native.pas existed, the
  from-scratch stack worked but could only be driven by a bespoke program, so
  an https:// caller had no way to reach it. If this file works, the stack is
  usable.

  Tls13NativeRegister is what installs the backend, and it is an explicit call
  rather than a side effect of `uses` — linking a unit must not silently decide
  which TLS stack a program trusts. After that line nothing here knows which
  backend it is talking to, which is why the first thing printed is the backend
  name.

  Usage: devtest_tls_native_seam <port> <hostname>
  Trust anchors come from SSL_CERT_FILE when set, else the system bundle.
  Driven by tools/tls_native_seam_devtest.sh; non-hermetic (needs openssl). }
uses sysutils, net, tls, tls13_native;
var
  fd: TNetSocket; c: TTlsConn; r: TTlsResult;
  req, resp: AnsiString; buf: array[0..4095] of Byte;
  got, put, i, port: Integer;
begin
  port := StrToInt(ParamStr(1));
  if TlsAvailable then begin WriteLn('a backend was registered behind our back'); Halt(1); end;
  Tls13NativeRegister;
  WriteLn('backend=', TlsActiveBackend.Name);
  fd := NetTcpConnect(NetLoopback(port));
  if fd < 0 then begin WriteLn('connect failed'); Halt(1); end;
  r := TlsHandshake(fd, tlsClient, ParamStr(2), c);
  if r <> tlsOk then
  begin
    WriteLn('handshake=FAIL: ', Tls13NativeLastError);
    NetClose(fd); Halt(1);
  end;
  WriteLn('handshake=ok');
  req := 'GET / HTTP/1.0' + Chr(13) + Chr(10) + 'Host: ' + ParamStr(2) + Chr(13) + Chr(10) + Chr(13) + Chr(10);
  r := TlsWrite(c, @req[1], Length(req), put);
  if r <> tlsOk then begin WriteLn('write=FAIL'); Halt(1); end;
  resp := '';
  for i := 1 to 20 do
  begin
    r := TlsRead(c, @buf[0], 4096, got);
    if r = tlsClosed then Break;
    if r <> tlsOk then begin WriteLn('read=FAIL: ', Tls13NativeLastError); Break; end;
    for put := 0 to got - 1 do resp := resp + Chr(buf[put]);
    if Pos('HTTP/', resp) > 0 then Break;
  end;
  TlsClose(c);
  NetClose(fd);
  WriteLn('response-head=', Copy(resp, 1, 15));
  if Pos('HTTP/', resp) > 0 then WriteLn('SEAM OK') else WriteLn('SEAM FAIL');
end.
