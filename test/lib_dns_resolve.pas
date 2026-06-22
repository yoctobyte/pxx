program lib_dns_resolve;
{ End-to-end test for dns_wire_blocking.DnsResolveA over loopback. A forked
  child acts as a mock DNS server: it receives the real query and replies with a
  canned 2-answer response, copying the query's transaction id so the resolver's
  id check passes. Fork (a process, not a thread) gives the request/response the
  concurrency a single call cannot; both sides are timeout-bounded so a lost
  datagram fails fast instead of hanging. }

uses platform, dns_wire_core, dns_wire_blocking;

var
  mock, pid, pr, status, rcode, count, i: Integer;
  qrecv: array[0..511] of Byte;
  resp: array[0..60] of Byte;
  fromA, boundA: LongWord;
  fromP, boundP: Integer;
  ips: TDnsIpv4Array;
  n: Int64;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  { Canned response for example.com: 2 A records (93.184.216.34/.35), answer
    names as compression pointers to the question. id is filled by the child. }
  for i := 0 to 60 do resp[i] := 0;
  resp[2] := $81; resp[3] := $80;          { flags: QR RD RA, rcode 0 }
  resp[5] := 1; resp[7] := 2;              { qd=1, an=2 }
  resp[12] := 7;
  resp[13] := Ord('e'); resp[14] := Ord('x'); resp[15] := Ord('a');
  resp[16] := Ord('m'); resp[17] := Ord('p'); resp[18] := Ord('l'); resp[19] := Ord('e');
  resp[20] := 3; resp[21] := Ord('c'); resp[22] := Ord('o'); resp[23] := Ord('m');
  resp[24] := 0; resp[26] := 1; resp[28] := 1;
  resp[29] := $C0; resp[30] := $0C; resp[32] := 1; resp[34] := 1;
  resp[38] := 60; resp[40] := 4;
  resp[41] := 93; resp[42] := 184; resp[43] := 216; resp[44] := 34;
  resp[45] := $C0; resp[46] := $0C; resp[48] := 1; resp[50] := 1;
  resp[54] := 60; resp[56] := 4;
  resp[57] := 93; resp[58] := 184; resp[59] := 216; resp[60] := 35;

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
    { CHILD: serve one query, echoing its id into the canned response. }
    pr := PalPoll(mock, PAL_POLL_IN, 3000);
    if pr > 0 then
    begin
      fromA := 0;
      fromP := 0;
      n := PalRecvFromIpv4(mock, @qrecv[0], 512, fromA, fromP);
      if n >= 2 then
      begin
        resp[0] := qrecv[0];
        resp[1] := qrecv[1];
        n := PalSendToIpv4(mock, @resp[0], 61, fromA, fromP);
      end;
    end;
    Halt(0);
  end;

  { PARENT: resolve through DnsResolveA pointed at the mock. }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rcode := DnsResolveA(PAL_NET_IP_LOOPBACK, boundP, 'example.com', ips, count, 2000);
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);

  writeln('rcode=', rcode);
  writeln('count=', count);
  Show('ip0', ips[0] = LongWord($5DB8D822));
  Show('ip1', ips[1] = LongWord($5DB8D823));
end.
