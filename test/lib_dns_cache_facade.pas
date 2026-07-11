program lib_dns_cache_facade;
{ End-to-end test for the facade's process-wide answer cache (dns.pas
  DnsGlobalCacheGet/Put wired into DnsResolveChase). A forked mock DNS server
  answers exactly ONE query for once.x (A 9.9.9.9, TTL 60) and exits. The first
  DnsResolveChase must hit the network; the second must be served from the
  cache (the server is gone — a real query could not succeed). After
  DnsCacheFlush a third lookup must fail, proving the second answer really came
  from the cache and not from a lingering server. Same fork/timeout discipline
  as lib_dns_chase. }

uses platform, dns_wire_core, dns_config, dns_wire_blocking, dns;

var
  mock, pid, pr, status, rcode, count, i: Integer;
  qrecv: array[0..511] of Byte;
  resp: array[0..511] of Byte;
  fromA, boundA: LongWord;
  fromP, boundP: Integer;
  ips, ns: TDnsIpv4Array;
  n: Int64;
  rlen: Integer;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  mock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if mock < 0 then
  begin
    writeln('mock-socket-fail');
    Halt(1);
  end;
  pr := PalSetSocketReuseAddr(mock, 1);
  pr := PalBindIpv4(mock, PAL_NET_IP_LOOPBACK, 0);
  if pr < 0 then
  begin
    writeln('mock-bind-fail');
    Halt(1);
  end;
  boundA := 0;
  boundP := 0;
  pr := PalGetSockNameIpv4(mock, boundA, boundP);

  pid := PalVfork;
  if pid = 0 then
  begin
    { CHILD: serve exactly one query — echo header+question, append one A
      record 9.9.9.9 with TTL 60 — then exit. }
    pr := PalPoll(mock, PAL_POLL_IN, 3000);
    if pr <= 0 then Halt(0);
    fromA := 0;
    fromP := 0;
    n := PalRecvFromIpv4(mock, @qrecv[0], 512, fromA, fromP);
    if n < 17 then Halt(0);
    for i := 0 to Integer(n) - 1 do resp[i] := qrecv[i];
    resp[2] := $81; resp[3] := $80;   { QR RD RA, rcode 0 }
    resp[7] := 1;                      { an=1 }
    rlen := Integer(n);
    resp[rlen] := $C0; resp[rlen + 1] := $0C;   { name: ptr to question }
    resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_A;
    resp[rlen + 4] := 0; resp[rlen + 5] := 1;
    resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 60;  { TTL 60 }
    resp[rlen + 10] := 0; resp[rlen + 11] := 4;   { rdlen }
    resp[rlen + 12] := 9; resp[rlen + 13] := 9;
    resp[rlen + 14] := 9; resp[rlen + 15] := 9;
    rlen := rlen + 16;
    n := PalSendToIpv4(mock, @resp[0], rlen, fromA, fromP);
    Halt(0);
  end;

  { PARENT }
  for i := 0 to DNS_MAX_IPS - 1 do
  begin
    ips[i] := 0;
    ns[i] := 0;
  end;
  ns[0] := PAL_NET_IP_LOOPBACK;

  { 1st lookup: real query against the mock; answer cached under TTL 60. }
  rcode := DnsResolveChase(ns, 1, boundP, 'once.x', ips, count, 2000);
  writeln('r1=', rcode);
  Show('ip1', (count = 1) and (ips[0] = LongWord($09090909)));

  { the one-shot server is now gone }
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);

  { 2nd lookup: must be served from the cache (no server to answer). }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  count := 0;
  rcode := DnsResolveChase(ns, 1, boundP, 'once.x', ips, count, 700);
  writeln('r2=', rcode);
  Show('cached', (count = 1) and (ips[0] = LongWord($09090909)));

  { 3rd lookup after a flush: no cache, no server -> must fail. }
  DnsCacheFlush;
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  count := 0;
  rcode := DnsResolveChase(ns, 1, boundP, 'once.x', ips, count, 700);
  Show('flushed-neg', rcode < 0);
end.
