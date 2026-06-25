program lib_http_pool_concurrent;
{ Concurrency-safety + eviction for the keep-alive pool (feature-own-net-http-lib).

  Two client coroutines call HttpGetPooledAsync to the SAME host:port at the same
  time. A correct (concurrency-safe) pool must NOT hand them the same socket: each
  in-flight request reserves its slot, so the second client opens a second
  connection. The server proves this by accepting TWICE — if the pool had shared
  one socket, the second accept would never return and the test would hang/fail.

  Per-host cap = 1: both clients still open their own socket while in flight (the
  server accepts twice), but as they release, the second conn over the cap is
  closed rather than pooled — so only ONE live conn remains. HttpPoolEvictIdle(0)
  then closes it; the count drops to 0. }
uses scheduler, asyncnet, http;

const PORT = 28811;

var
  gAccepts: Integer;
  gBody1, gBody2: AnsiString;
  gServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var lfd, c1, c2: Integer; buf: array[0..2047] of Byte; n: Int64; resp: AnsiString;
begin
  resp := 'HTTP/1.1 200 OK'#13#10'Content-Length: 3'#13#10'Connection: keep-alive'#13#10#13#10'hey';
  lfd := TcpListen(PORT);
  c1 := TcpAccept(lfd);                   { first concurrent client }
  c2 := TcpAccept(lfd);                   { second — proves no socket sharing }
  gAccepts := 2;
  n := TcpRecv(c1, @buf[0], 2048);  TcpSend(c1, @resp[1], Length(resp));
  n := TcpRecv(c2, @buf[0], 2048);  TcpSend(c2, @resp[1], Length(resp));
  TcpClose(c1);  TcpClose(c2);  TcpClose(lfd);
  gServerDone := True;
end;

procedure Client1Co(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetPooledAsync('http://127.0.0.1:28811/a');
  gBody1 := r.Body;
end;

procedure Client2Co(arg: Pointer);
var r: THttpResponse;
begin
  r := HttpGetPooledAsync('http://127.0.0.1:28811/b');
  gBody2 := r.Body;
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var countLive, countEvicted: Integer;
begin
  gAccepts := 0; gBody1 := ''; gBody2 := ''; gServerDone := False;
  HttpPoolSetMaxPerHost(1);                { keep at most one idle conn per host }
  Spawn(@ServerCo, nil);
  Spawn(@Client1Co, nil);
  Spawn(@Client2Co, nil);
  RunUntilDone;

  countLive := HttpPoolCount;             { cap=1 → only one conn kept }
  HttpPoolEvictIdle(0);                    { idle >= 0ms → close every free conn }
  countEvicted := HttpPoolCount;
  HttpPoolClose;

  SayBool('server-done', gServerDone);
  SayBool('two-accepts', gAccepts = 2);    { proves the two clients did NOT share }
  SayBool('body1', gBody1 = 'hey');
  SayBool('body2', gBody2 = 'hey');
  SayBool('count-capped', countLive = 1);  { per-host cap trimmed the extra }
  SayBool('count-after-evict', countEvicted = 0);
end.
