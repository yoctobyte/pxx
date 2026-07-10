program lib_dns_aaaa;
{ End-to-end test for dns_wire_blocking.DnsResolveAAAA over loopback: a forked
  mock DNS server echoes the query header+question and appends one AAAA answer
  (2001:db8::1). Same fork/timeout discipline as lib_dns_resolve. }

uses platform, dns_wire_core, dns_wire_blocking;

var
  mock, pid, pr, status, rcode, count, i: Integer;
  qrecv: array[0..511] of Byte;
  resp: array[0..511] of Byte;
  fromA, boundA: LongWord;
  fromP, boundP: Integer;
  ips: TDnsIpv6Array;
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
    { CHILD: echo the query header+question, append one AAAA answer. }
    pr := PalPoll(mock, PAL_POLL_IN, 3000);
    if pr > 0 then
    begin
      fromA := 0;
      fromP := 0;
      n := PalRecvFromIpv4(mock, @qrecv[0], 512, fromA, fromP);
      if n >= 17 then
      begin
        for i := 0 to Integer(n) - 1 do resp[i] := qrecv[i];
        resp[2] := $81; resp[3] := $80;   { QR RD RA, rcode 0 }
        resp[7] := 1;                      { an=1 }
        rlen := Integer(n);
        resp[rlen] := $C0; resp[rlen + 1] := $0C;   { name -> question }
        resp[rlen + 2] := 0; resp[rlen + 3] := DNS_TYPE_AAAA;
        resp[rlen + 4] := 0; resp[rlen + 5] := 1;   { class IN }
        resp[rlen + 6] := 0; resp[rlen + 7] := 0; resp[rlen + 8] := 0; resp[rlen + 9] := 0;
        resp[rlen + 10] := 0; resp[rlen + 11] := 16; { rdlen }
        for i := 0 to 15 do resp[rlen + 12 + i] := 0;
        resp[rlen + 12] := $20; resp[rlen + 13] := $01;
        resp[rlen + 14] := $0D; resp[rlen + 15] := $B8;
        resp[rlen + 27] := 1;
        rlen := rlen + 28;
        n := PalSendToIpv4(mock, @resp[0], rlen, fromA, fromP);
      end;
    end;
    Halt(0);
  end;

  { PARENT }
  rcode := DnsResolveAAAA(PAL_NET_IP_LOOPBACK, boundP, 'v6.example', ips, count, 2000);
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);

  writeln('rcode=', rcode);
  writeln('count=', count);
  Show('ip6', (ips[0][0] = $20) and (ips[0][1] = $01) and (ips[0][2] = $0D) and
    (ips[0][3] = $B8) and (ips[0][4] = 0) and (ips[0][15] = 1));
end.
