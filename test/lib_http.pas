program lib_http;
{ Smoke for the native http client's pure helpers (feature-synapse-compile-check
  + own net lib): URL parse, request build, response parse. No network — the
  transport (connect/send/recv) is covered by lib_sockets / lib_net. }
uses http;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  host, path: AnsiString;
  port: Integer;
  isTls, okUrl: Boolean;
  req: AnsiString;
  resp: THttpResponse;
begin
  { URL parse: host + path. }
  okUrl := HttpParseUrl('http://example.com/index.html', host, port, path, isTls);
  SayBool('url-ok', okUrl);
  SayBool('url-host', host = 'example.com');
  SayBool('url-port', port = 80);
  SayBool('url-path', path = '/index.html');
  SayBool('url-notls', not isTls);

  { URL parse: explicit port, no path -> '/'. }
  HttpParseUrl('http://10.0.0.1:8080', host, port, path, isTls);
  SayBool('url-port2', (host = '10.0.0.1') and (port = 8080) and (path = '/'));

  { https recognised + flagged. }
  HttpParseUrl('https://secure.example/', host, port, path, isTls);
  SayBool('url-tls', isTls and (port = 443));

  { non-http rejected. }
  SayBool('url-bad', not HttpParseUrl('ftp://x/', host, port, path, isTls));

  { Request build: well-formed GET. }
  req := HttpBuildRequest('GET', 'example.com', '/', '', '');
  SayBool('req-line', Copy(req, 1, 16) = 'GET / HTTP/1.1'#13#10);
  SayBool('req-host', Pos('Host: example.com'#13#10, req) > 0);
  SayBool('req-close', Pos('Connection: close'#13#10, req) > 0);
  SayBool('req-end', Copy(req, Length(req) - 3, 4) = #13#10#13#10);

  { Request build: POST body adds Content-Length. }
  req := HttpBuildRequest('POST', 'h', '/p', 'Content-Type: text/plain'#13#10, 'hello');
  SayBool('req-clen', Pos('Content-Length: 5'#13#10, req) > 0);
  SayBool('req-ctype', Pos('Content-Type: text/plain'#13#10, req) > 0);
  SayBool('req-body', Copy(req, Length(req) - 4, 5) = 'hello');

  { Response parse: status, headers, body. }
  HttpParseResponse('HTTP/1.1 200 OK'#13#10'Server: x'#13#10'Content-Length: 2'#13#10#13#10'hi', resp);
  SayBool('resp-ok', resp.Ok);
  SayBool('resp-status', resp.Status = 200);
  SayBool('resp-reason', resp.Reason = 'OK');
  SayBool('resp-hdr', Pos('Server: x', resp.Headers) > 0);
  SayBool('resp-body', resp.Body = 'hi');

  { Response parse: 404, no body. }
  HttpParseResponse('HTTP/1.1 404 Not Found'#13#10'X: y'#13#10#13#10, resp);
  SayBool('resp-404', (resp.Status = 404) and (resp.Reason = 'Not Found') and (resp.Body = ''));
end.
