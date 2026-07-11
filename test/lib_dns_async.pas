program lib_dns_async;
{ End-to-end async DNS over the coroutine reactor (feature-own-net-http-lib):
  a loopback UDP DNS server coroutine answers a canned A record; a client
  coroutine resolves through DnsQueryAAsync. Both run on one thread, reactor-
  driven — proves async UDP + the DNS wire round-trip without external network. }
uses scheduler, platform, dns_wire_core, dns_wire_blocking, dns_cache, dns_async, dns_cached;

const
  PORT = 28766;
  CPORT = 28767;   { chase server }
  DPORT = 28768;   { deaf server (never answers) — timeout check }
  SPORT = 28769;   { AAAA server }
  KPORT = 28770;   { cache server (counts queries) }

var
  gRcode: Integer;
  gCount: Integer;
  gIp:    LongWord;
  gServerDone: Boolean;
  gChaseRcode, gChaseCount: Integer;
  gChaseIp: LongWord;
  gChaseServerDone: Boolean;
  gTimeoutRc: Integer;
  gV6Rcode, gV6Count: Integer;
  gV6Ok, gV6ServerDone: Boolean;
  gKQueries: Integer;          { how many queries the cache server actually got }
  gK1Ip, gK2Ip: LongWord;
  gK1Count, gK2Count: Integer;
  gKServerDone: Boolean;

procedure ServerCo(arg: Pointer);
var
  sock: Integer; rc: Integer;
  qbuf: array[0..1535] of Byte;
  resp: array[0..1599] of Byte;
  n: Int64; fromAddr: LongWord; fromPort: Integer;
  i, qlen, off: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, PORT);
  rc := PalSetSocketNonBlocking(sock, 1);

  WaitReadable(sock);
  n := PalRecvFromIpv4(sock, @qbuf[0], 1536, fromAddr, fromPort);
  qlen := Integer(n);

  { Echo the query as the response prefix (keeps the id + question), then flip
    to an answer: QR=1, RA=1, RCODE=0, ANCOUNT=1, append one A record = 1.2.3.4. }
  for i := 0 to qlen - 1 do resp[i] := qbuf[i];
  resp[2] := $81;            { QR=1, Opcode=0, AA=0, TC=0, RD=1 }
  resp[3] := $80;            { RA=1, RCODE=0 }
  resp[6] := $00; resp[7] := $01;   { ANCOUNT = 1 }

  off := qlen;
  resp[off]   := $C0; resp[off+1] := $0C;   { name -> pointer to offset 12 }
  resp[off+2] := $00; resp[off+3] := $01;   { TYPE  A }
  resp[off+4] := $00; resp[off+5] := $01;   { CLASS IN }
  resp[off+6] := $00; resp[off+7] := $00;
  resp[off+8] := $00; resp[off+9] := $3C;   { TTL = 60 }
  resp[off+10] := $00; resp[off+11] := $04; { RDLENGTH = 4 }
  resp[off+12] := 1; resp[off+13] := 2; resp[off+14] := 3; resp[off+15] := 4;

  rc := Integer(PalSendToIpv4(sock, @resp[0], off + 16, fromAddr, fromPort));
  rc := PalSocketClose(sock);
  gServerDone := True;
end;

procedure ClientCo(arg: Pointer);
var ips: TDnsIpv4Array; cnt: Integer;
begin
  cnt := 0;
  gRcode := DnsQueryAAsync(PAL_NET_IP_LOOPBACK, PORT, 'test.local', ips, cnt);
  gCount := cnt;
  if cnt > 0 then gIp := ips[0];
end;

{ Chase server: two queries on CPORT. First (www..., leading label length 3)
  gets a CNAME to real.x and no address; second gets A 5.6.7.8. Mirrors the
  blocking-side lib_dns_chase mock, but as a coroutine instead of a fork. }
procedure ChaseServerCo(arg: Pointer);
var
  sock, rc, q, i, rlen: Integer;
  qbuf: array[0..511] of Byte;
  resp: array[0..511] of Byte;
  n: Int64; fromAddr: LongWord; fromPort: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, CPORT);
  rc := PalSetSocketNonBlocking(sock, 1);
  for q := 1 to 2 do
  begin
    WaitReadable(sock);
    n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
    while n = PAL_NET_EAGAIN do
    begin
      WaitReadable(sock);
      n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
    end;
    if n < 17 then begin rc := PalSocketClose(sock); Exit; end;
    for i := 0 to Integer(n) - 1 do resp[i] := qbuf[i];
    resp[2] := $81; resp[3] := $80;
    resp[7] := 1;
    rlen := Integer(n);
    resp[rlen] := $C0; resp[rlen + 1] := $0C;
    if qbuf[12] = 3 then
    begin
      { www.x -> CNAME real.x }
      resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_CNAME;
      resp[rlen + 4] := 0; resp[rlen + 5] := 1;
      resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
      resp[rlen + 10] := 0; resp[rlen + 11] := 8;
      resp[rlen + 12] := 4;
      resp[rlen + 13] := Ord('r'); resp[rlen + 14] := Ord('e');
      resp[rlen + 15] := Ord('a'); resp[rlen + 16] := Ord('l');
      resp[rlen + 17] := 1; resp[rlen + 18] := Ord('x');
      resp[rlen + 19] := 0;
      rlen := rlen + 20;
    end
    else
    begin
      { real.x -> A 5.6.7.8 }
      resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_A;
      resp[rlen + 4] := 0; resp[rlen + 5] := 1;
      resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
      resp[rlen + 10] := 0; resp[rlen + 11] := 4;
      resp[rlen + 12] := 5; resp[rlen + 13] := 6;
      resp[rlen + 14] := 7; resp[rlen + 15] := 8;
      rlen := rlen + 16;
    end;
    n := PalSendToIpv4(sock, @resp[0], rlen, fromAddr, fromPort);
  end;
  rc := PalSocketClose(sock);
  gChaseServerDone := True;
end;

procedure ChaseClientCo(arg: Pointer);
var
  ips, ns: TDnsIpv4Array;
  cnt, i: Integer;
begin
  for i := 0 to DNS_MAX_IPS - 1 do begin ips[i] := 0; ns[i] := 0; end;
  ns[0] := PAL_NET_IP_LOOPBACK;
  cnt := 0;
  gChaseRcode := DnsResolveChaseAsync(ns, 1, CPORT, 'www.x', ips, cnt, 2000);
  gChaseCount := cnt;
  if cnt > 0 then gChaseIp := ips[0];
end;

{ Timeout: a bound socket that never answers; 200ms budget must come back
  PAL_NET_ETIMEDOUT instead of hanging the reactor. }
procedure TimeoutClientCo(arg: Pointer);
var
  ips: TDnsIpv4Array;
  cnt: Integer;
  cname: string;
  deaf, rc: Integer;
begin
  deaf := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(deaf, PAL_NET_IP_LOOPBACK, DPORT);
  cnt := 0;
  cname := '';
  gTimeoutRc := DnsQueryAAsyncEx(PAL_NET_IP_LOOPBACK, DPORT, 'dead.x', ips, cnt, cname, 200);
  rc := PalSocketClose(deaf);
end;

{ AAAA server: echo query header+question, append one AAAA answer 2001:db8::1. }
procedure V6ServerCo(arg: Pointer);
var
  sock, rc, i, rlen: Integer;
  qbuf: array[0..511] of Byte;
  resp: array[0..511] of Byte;
  n: Int64; fromAddr: LongWord; fromPort: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, SPORT);
  rc := PalSetSocketNonBlocking(sock, 1);
  WaitReadable(sock);
  n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
  while n = PAL_NET_EAGAIN do
  begin
    WaitReadable(sock);
    n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
  end;
  if n >= 17 then
  begin
    for i := 0 to Integer(n) - 1 do resp[i] := qbuf[i];
    resp[2] := $81; resp[3] := $80;
    resp[7] := 1;
    rlen := Integer(n);
    resp[rlen] := $C0; resp[rlen + 1] := $0C;
    resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_AAAA;
    resp[rlen + 4] := 0; resp[rlen + 5] := 1;
    resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
    resp[rlen + 10] := 0; resp[rlen + 11] := 16;
    for i := 0 to 15 do resp[rlen + 12 + i] := 0;
    resp[rlen + 12] := $20; resp[rlen + 13] := $01;
    resp[rlen + 14] := $0D; resp[rlen + 15] := $B8;
    resp[rlen + 27] := 1;
    rlen := rlen + 28;
    n := PalSendToIpv4(sock, @resp[0], rlen, fromAddr, fromPort);
  end;
  rc := PalSocketClose(sock);
  gV6ServerDone := True;
end;

procedure V6ClientCo(arg: Pointer);
var ips: TDnsIpv6Array; cnt: Integer;
begin
  cnt := 0;
  gV6Rcode := DnsQueryAAAAAsync(PAL_NET_IP_LOOPBACK, SPORT, 'v6.x', ips, cnt, 2000);
  gV6Count := cnt;
  if cnt > 0 then
    gV6Ok := (ips[0][0] = $20) and (ips[0][1] = $01) and (ips[0][2] = $0D) and
             (ips[0][3] = $B8) and (ips[0][4] = 0) and (ips[0][15] = 1);
end;

{ Cache server: answers A queries with TTL=60 and 9.9.9.9, counting how many
  queries arrive. Serves up to 2 so a bug that misses the cache is observable
  (gKQueries would reach 2); a working cache leaves it at 1. }
procedure CacheServerCo(arg: Pointer);
var
  sock, rc, q, i, rlen: Integer;
  qbuf: array[0..511] of Byte;
  resp: array[0..511] of Byte;
  n: Int64; fromAddr: LongWord; fromPort: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, KPORT);
  rc := PalSetSocketNonBlocking(sock, 1);
  for q := 1 to 2 do
  begin
    if not WaitReadableTimeout(sock, 800) then
    begin
      n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
      if n = PAL_NET_EAGAIN then Break;   { no second query -> cache worked }
    end
    else
      n := PalRecvFromIpv4(sock, @qbuf[0], 512, fromAddr, fromPort);
    if n < 17 then Break;
    gKQueries := gKQueries + 1;
    for i := 0 to Integer(n) - 1 do resp[i] := qbuf[i];
    resp[2] := $81; resp[3] := $80;
    resp[7] := 1;                    { an=1 }
    rlen := Integer(n);
    resp[rlen] := $C0; resp[rlen + 1] := $0C;
    resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_A;
    resp[rlen + 4] := 0; resp[rlen + 5] := 1;
    resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 60;  { TTL 60 }
    resp[rlen + 10] := 0; resp[rlen + 11] := 4;
    resp[rlen + 12] := 9; resp[rlen + 13] := 9; resp[rlen + 14] := 9; resp[rlen + 15] := 9;
    rlen := rlen + 16;
    n := PalSendToIpv4(sock, @resp[0], rlen, fromAddr, fromPort);
  end;
  rc := PalSocketClose(sock);
  gKServerDone := True;
end;

procedure CacheClientCo(arg: Pointer);
var
  cache: TDnsCache;
  ns, ips: TDnsIpv4Array;
  cnt, rcode, i: Integer;
begin
  DnsCacheInit(cache);
  for i := 0 to DNS_MAX_IPS - 1 do begin ips[i] := 0; ns[i] := 0; end;
  ns[0] := PAL_NET_IP_LOOPBACK;
  { first lookup at t=1000ms — miss, queries the server, caches TTL 60s }
  cnt := 0; rcode := 0;
  DnsQueryAListCachedAsync(cache, ns, 1, KPORT, 'cached.x', 1000, ips, cnt, rcode, 2000);
  gK1Count := cnt; if cnt > 0 then gK1Ip := ips[0];
  { second lookup at t=5000ms (< 60s later) — must be a cache hit, no query }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  cnt := 0; rcode := 0;
  DnsQueryAListCachedAsync(cache, ns, 1, KPORT, 'cached.x', 5000, ips, cnt, rcode, 2000);
  gK2Count := cnt; if cnt > 0 then gK2Ip := ips[0];
end;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  gRcode := -999; gCount := 0; gIp := 0; gServerDone := False;
  gChaseRcode := -999; gChaseCount := 0; gChaseIp := 0; gChaseServerDone := False;
  gTimeoutRc := -999;
  gV6Rcode := -999; gV6Count := 0; gV6Ok := False; gV6ServerDone := False;
  gKQueries := 0; gK1Ip := 0; gK2Ip := 0; gK1Count := 0; gK2Count := 0; gKServerDone := False;
  Spawn(@ServerCo, nil);
  Spawn(@ClientCo, nil);
  Spawn(@ChaseServerCo, nil);
  Spawn(@ChaseClientCo, nil);
  Spawn(@TimeoutClientCo, nil);
  Spawn(@V6ServerCo, nil);
  Spawn(@V6ClientCo, nil);
  Spawn(@CacheServerCo, nil);
  Spawn(@CacheClientCo, nil);
  RunUntilDone;

  SayBool('server-done', gServerDone);
  SayBool('rcode', gRcode = 0);
  SayBool('count', gCount = 1);
  SayBool('ip', gIp = $01020304);   { 1.2.3.4 host byte order }
  SayBool('chase-server-done', gChaseServerDone);
  SayBool('chase-rcode', gChaseRcode = 0);
  SayBool('chase-count', gChaseCount = 1);
  SayBool('chase-ip', gChaseIp = $05060708);
  SayBool('timeout', gTimeoutRc = PAL_NET_ETIMEDOUT);
  SayBool('v6-server-done', gV6ServerDone);
  SayBool('v6-rcode', gV6Rcode = 0);
  SayBool('v6-count', gV6Count = 1);
  SayBool('v6-ip', gV6Ok);
  SayBool('cache-1st', (gK1Count = 1) and (gK1Ip = LongWord($09090909)));
  SayBool('cache-2nd', (gK2Count = 1) and (gK2Ip = LongWord($09090909)));
  SayBool('cache-1query', gKQueries = 1);   { second lookup served from cache }
end.
