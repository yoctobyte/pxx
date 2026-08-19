program lib_mimic_urllib_request_server;
{ The fixed-route HTTP server that test/lib_mimic_urllib_request.npy is measured
  against — and, critically, that CPython is measured against too.

  WHY A SERVER AND NOT A RECORDED FIXTURE. The point of this test is that our
  `urlopen` and CPython's `urlopen` do the same thing, and the only way to
  compare them honestly is to point both at the SAME server and diff the two
  clients' output. A canned response file would compare us against our own idea
  of what a server says, which is the failure mode the codecs suite avoids by
  diffing CPython (devdocs/dev/python-compat-tiers.md: "a shim is measured
  against the real thing").

  Routes are deliberately boring and fully deterministic — no dates, no random
  boundaries, nothing that would differ between the two runs and show up as a
  diff that is not a bug.

  Serves until it is asked for /quit, so one server process covers both client
  runs; the harness kills it if a client dies before asking.

  Track B (libraries). Gate: make lib-test. }
uses scheduler, asyncnet, http, sysutils;

const
  { 0 = let the kernel pick a free port. It used to be 28901, and a hardcoded
    port is a shared global: two copies of lib-test on one box fight over it,
    which is exactly what Track T's watcher host does by design
    (bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable). This
    server was already the well-behaved one — it checks the listen and announces
    `ready <port>` on stdout instead of making the harness sleep — so the only
    thing needed was to announce the port it ACTUALLY got and let the harness
    read it from there. An explicit port on the command line still overrides,
    for a caller that needs a known one. }
  DEFAULT_PORT = 0;

var
  gQuit: Boolean;
  gPort: Integer;

function Handler(const req: THttpRequest): AnsiString;
var ct, body: AnsiString;
begin
  if req.Path = '/hello' then
    Handler := HttpBuildResponse(200, 'OK',
      'Content-Type: text/plain; charset=utf-8'#13#10 +
      'X-Note: first'#13#10 +
      'Connection: keep-alive'#13#10,
      'hello, world'#10'second line'#10)

  else if req.Path = '/notfound' then
    Handler := HttpBuildResponse(404, 'Not Found',
      'Content-Type: text/plain'#13#10 +
      'Connection: keep-alive'#13#10,
      'no such page')

  else if req.Path = '/redirect' then
    { relative Location on purpose — resolving it is HttpResolveUrl's job and
      a client that got it wrong would fetch the wrong url, not fail loudly }
    Handler := HttpBuildResponse(302, 'Found',
      'Location: /hello'#13#10 +
      'Connection: keep-alive'#13#10,
      '')

  else if req.Path = '/multi' then
    { the repeated-header case: a dict-shaped headers object silently keeps one
      of these, which is exactly what get_all exists to catch }
    Handler := HttpBuildResponse(200, 'OK',
      'Content-Type: text/plain'#13#10 +
      'X-Note: alpha'#13#10 +
      'X-Note: beta'#13#10 +
      'Connection: keep-alive'#13#10,
      'multi')

  else if req.Path = '/echo' then
  begin
    ct := HttpRequestHeader(req, 'Content-Type');
    body := req.Body;
    Handler := HttpBuildResponse(200, 'OK',
      'Content-Type: text/plain'#13#10 +
      'Connection: keep-alive'#13#10,
      'm=' + req.Method + ' ct=' + ct + ' b=' + body);
  end

  else if req.Path = '/quit' then
  begin
    gQuit := True;
    Handler := HttpBuildResponse(200, 'OK', 'Connection: close'#13#10, 'bye');
  end

  else
    Handler := HttpBuildResponse(404, 'Not Found',
      'Connection: keep-alive'#13#10, 'unrouted: ' + req.Path);
end;

procedure ServerCo(arg: Pointer);
var lfd, cfd: Integer;
begin
  lfd := TcpListen(gPort);
  if lfd < 0 then
  begin
    writeln('listen-failed');
    Exit;
  end;
  { With gPort = 0 the kernel chose; read back which one, because the harness and
    both clients learn the port from the `ready` line below and nowhere else. }
  gPort := TcpLocalPort(lfd);
  if gPort <= 0 then
  begin
    writeln('listen-failed');
    TcpClose(lfd);
    Exit;
  end;
  { Announce readiness on stdout so the harness can wait for the line instead
    of sleeping a guessed number of seconds — a sleep is how this kind of test
    becomes flaky on a loaded box. }
  writeln('ready ', gPort);
  Flush(Output);
  while not gQuit do
  begin
    cfd := TcpAccept(lfd);
    if cfd < 0 then Break;
    { one connection may carry several keep-alive requests }
    HttpServeConn(cfd, @Handler, 16, True);
    TcpClose(cfd);
  end;
  TcpClose(lfd);
end;

begin
  gQuit := False;
  gPort := DEFAULT_PORT;
  if ParamCount >= 1 then gPort := StrToIntDef(ParamStr(1), DEFAULT_PORT);
  Spawn(@ServerCo, nil);
  RunUntilDone;
end.
