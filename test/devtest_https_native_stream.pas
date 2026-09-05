program devtest_https_native_stream;
{ A LARGE body over https, on both the blocking and the reactor path, onto the
  native TLS 1.3 backend.

  WHY THIS IS NOT COVERED BY devtest_https_native_async. That row does one GET
  of a status page -- a handshake plus a couple of application-data records. The
  EAGAIN handling that the data path inherited from the shared helpers on
  2026-09-01 is therefore exercised once and shallowly, and the shape that broke
  the HANDSHAKE for months (a would-block read as end-of-stream) has an exact
  twin in the data path: a short read that silently truncates a body. A body of
  a few hundred bytes fits in one socket buffer and can complete without a
  single would-block, so the row that exists cannot fail that way.

  THE ASSERTION IS THE LENGTH AND A CHECKSUM, and the pair is deliberate.
  Truncation is the failure this is aimed at and only a LENGTH sees it; a
  checksum alone passes on a body that stopped early if the assertion is
  computed from the same short string. Reordering or a dropped record in the
  middle keeps the length and moves the sum, so neither quantity subsumes the
  other.

  BOTH PATHS IN ONE BINARY, chosen by argv[2], so the sync run is a positive
  control for the async one: if async goes red and sync stays green, the reactor
  is implicated and the server, the certificate and the body are not. That is
  the same control that made the 2026-09-01 handshake defect legible, and it
  only works because both runs fetch the identical URL.

  Usage: devtest_https_native_stream <url> sync|async
  Trust anchors from SSL_CERT_FILE when set, else the system bundle.
  Driven by tools/tls_native_seam_devtest.sh; non-hermetic (needs openssl). }
uses sysutils, http, tls, tls13_native, scheduler;

var
  gUrl: AnsiString;
  gStatus, gLen: Integer;
  gSum: Int64;
  gOk: Boolean;
  gErr: AnsiString;

procedure Measure(const r: THttpResponse);
var i: Integer; s: Int64;
begin
  gStatus := r.Status;
  gOk := r.Ok;
  if not r.Ok then
  begin
    gErr := Tls13NativeLastError;
    Exit;
  end;
  gLen := Length(r.Body);
  s := 0;
  for i := 1 to Length(r.Body) do s := s + Ord(r.Body[i]);
  gSum := s;
end;

procedure Body(arg: Pointer);
begin
  Measure(HttpRequestAsync('GET', gUrl, '', ''));
end;

begin
  Tls13NativeRegister;
  gUrl := ParamStr(1);
  gStatus := 0; gLen := 0; gSum := 0; gOk := False; gErr := '';
  WriteLn('backend=', TlsActiveBackend.Name);
  if ParamStr(2) = 'async' then
  begin
    Spawn(@Body, nil);
    RunUntilDone;
  end
  else
    Measure(HttpGet(gUrl));
  WriteLn('status=', gStatus);
  WriteLn('len=', gLen);
  WriteLn('sum=', gSum);
  if gOk and (gStatus = 200) then WriteLn('STREAM OK')
  else WriteLn('STREAM FAIL: ', gErr);
end.
