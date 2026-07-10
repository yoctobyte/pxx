program lib_dns_chase;
{ End-to-end test for the facade's CNAME chase (dns.DnsResolveChase) over
  loopback. A forked mock DNS server answers two queries: the first (www.x)
  with a CNAME to real.x and no address, the second (real.x) with an A record.
  The resolver must follow the alias with a second query and come back with
  1.2.3.4. Same fork/timeout discipline as lib_dns_resolve. }

uses platform, dns_wire_core, dns_config, dns_wire_blocking, dns;

var
  mock, pid, pr, status, rcode, count, i, q: Integer;
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
    { CHILD: serve two queries. Echo the query header+question, then append
      one answer: a CNAME (real.x) when the first label is "www", an A record
      (1.2.3.4) when it is "real". }
    for q := 1 to 2 do
    begin
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
      { answer name: pointer to the question name }
      resp[rlen] := $C0; resp[rlen + 1] := $0C;
      if qrecv[12] = 3 then
      begin
        { www.x -> CNAME real.x }
        resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_CNAME;
        resp[rlen + 4] := 0; resp[rlen + 5] := 1;
        resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
        resp[rlen + 10] := 0; resp[rlen + 11] := 8;   { rdlen }
        resp[rlen + 12] := 4;
        resp[rlen + 13] := Ord('r'); resp[rlen + 14] := Ord('e');
        resp[rlen + 15] := Ord('a'); resp[rlen + 16] := Ord('l');
        resp[rlen + 17] := 1; resp[rlen + 18] := Ord('x');
        resp[rlen + 19] := 0;
        rlen := rlen + 20;
      end
      else
      begin
        { real.x -> A 1.2.3.4 }
        resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_A;
        resp[rlen + 4] := 0; resp[rlen + 5] := 1;
        resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
        resp[rlen + 10] := 0; resp[rlen + 11] := 4;   { rdlen }
        resp[rlen + 12] := 1; resp[rlen + 13] := 2;
        resp[rlen + 14] := 3; resp[rlen + 15] := 4;
        rlen := rlen + 16;
      end;
      n := PalSendToIpv4(mock, @resp[0], rlen, fromA, fromP);
    end;
    Halt(0);
  end;

  { PARENT: chase www.x through the mock; must land on real.x's A record. }
  for i := 0 to DNS_MAX_IPS - 1 do
  begin
    ips[i] := 0;
    ns[i] := 0;
  end;
  ns[0] := PAL_NET_IP_LOOPBACK;
  rcode := DnsResolveChase(ns, 1, boundP, 'www.x', ips, count, 2000);
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);

  writeln('rcode=', rcode);
  writeln('count=', count);
  Show('chased', ips[0] = LongWord($01020304));
end.
