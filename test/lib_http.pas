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
  hdrs: THttpHeaders;
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

  { Header lookup (case-insensitive, trimmed). }
  SayBool('hdr-ci', HttpHeaderValue('Content-Type:  text/html '#13#10'X: 1', 'content-type') = 'text/html');
  SayBool('hdr-miss', HttpHeaderValue('A: b'#13#10, 'nope') = '');

  { Chunked decode (standalone helper): '5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n'. }
  SayBool('dechunk', HttpDechunk('5'#13#10'hello'#13#10'6'#13#10' world'#13#10'0'#13#10#13#10) = 'hello world');

  { Response with chunked body is decoded. }
  HttpParseResponse('HTTP/1.1 200 OK'#13#10'Transfer-Encoding: chunked'#13#10#13#10 +
                    '4'#13#10'Wiki'#13#10'5'#13#10'pedia'#13#10'0'#13#10#13#10, resp);
  SayBool('resp-chunked', resp.Body = 'Wikipedia');

  { Content-Length trims trailing junk (e.g. start of a pipelined response). }
  HttpParseResponse('HTTP/1.1 200 OK'#13#10'Content-Length: 2'#13#10#13#10'hiEXTRA', resp);
  SayBool('resp-clen-trim', resp.Body = 'hi');

  { Methods produce the right request line (HEAD/PUT/DELETE via HttpBuildRequest,
    which the wrappers call). }
  SayBool('req-head', Copy(HttpBuildRequest('HEAD', 'h', '/x', '', ''), 1, 18) = 'HEAD /x HTTP/1.1'#13#10);
  req := HttpBuildRequest('PUT', 'h', '/r', '', 'data');
  SayBool('req-put', (Copy(req, 1, 17) = 'PUT /r HTTP/1.1'#13#10) and (Pos('Content-Length: 4'#13#10, req) > 0));
  SayBool('req-delete', Copy(HttpBuildRequest('DELETE', 'h', '/r', '', ''), 1, 20) = 'DELETE /r HTTP/1.1'#13#10);

  { Location resolution: absolute / absolute-path / relative / default-port. }
  SayBool('url-abs', HttpResolveUrl('http://a/x', 'http://b/y') = 'http://b/y');
  SayBool('url-abspath', HttpResolveUrl('http://host:8080/a/b', '/c') = 'http://host:8080/c');
  SayBool('url-rel', HttpResolveUrl('http://host/a/b', 'c') = 'http://host/a/c');
  SayBool('url-defport', HttpResolveUrl('http://host/a', '/x') = 'http://host/x');

  { Structured header API: parse / count / get (ci) / has / iterate. }
  hdrs := HttpParseHeaders('Content-Type: text/html'#13#10'Set-Cookie: a=1'#13#10'Set-Cookie: b=2'#13#10);
  SayBool('hdrs-count', hdrs.Count = 3);
  SayBool('hdrs-get-ci', HttpHeadersGet(hdrs, 'content-type') = 'text/html');
  SayBool('hdrs-first', HttpHeadersGet(hdrs, 'Set-Cookie') = 'a=1');    { first of repeats }
  SayBool('hdrs-has', HttpHeadersHas(hdrs, 'set-cookie') and not HttpHeadersHas(hdrs, 'nope'));
  SayBool('hdrs-iter', (HttpHeaderName(hdrs, 0) = 'Content-Type') and (HttpHeaderVal(hdrs, 2) = 'b=2'));

  { Structured headers off a parsed response (the convenience seam). }
  HttpParseResponse('HTTP/1.1 200 OK'#13#10'Content-Type: text/plain'#13#10'X-A: 1'#13#10#13#10'body', resp);
  hdrs := HttpResponseHeaders(resp);
  SayBool('resp-hdrs-count', hdrs.Count = 2);
  SayBool('resp-hdr-ci', HttpResponseHeader(resp, 'content-type') = 'text/plain');
  SayBool('resp-hdr-absent', HttpResponseHeader(resp, 'nope') = '');

  { URL percent-encoding. }
  SayBool('urlenc', HttpUrlEncode('a b&c=d/e') = 'a%20b%26c%3Dd%2Fe');
  SayBool('urlenc-keep', HttpUrlEncode('Aa9-_.~') = 'Aa9-_.~');
  SayBool('urldec', HttpUrlDecode('a%20b%26c') = 'a b&c');
  SayBool('urldec-plus', HttpUrlDecode('a+b') = 'a b');
  SayBool('url-roundtrip', HttpUrlDecode(HttpUrlEncode('x y/z?q=1')) = 'x y/z?q=1');

  { Query/form builder: first pair no '&', encodes name+value. }
  SayBool('query1', HttpQueryAdd('', 'a', '1') = 'a=1');
  SayBool('query2', HttpQueryAdd(HttpQueryAdd('', 'a', '1'), 'b', '2 3') = 'a=1&b=2%203');
  SayBool('query-enc', HttpQueryAdd('', 'q', 'a&b') = 'q=a%26b');
end.
