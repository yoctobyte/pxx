program lib_dns_multins;
{ Multi-nameserver retry: the first nameserver is dead (127.0.0.2, nothing
  listening -> times out), so DnsResolveAList must move on to the second
  (127.0.0.1, the forked mock) and still resolve. Short per-server timeout keeps
  the dead-server wait brief. }

uses platform, dns_wire_core, dns_wire_blocking;

const
  IP_LOOPBACK2 = $7F000002;   { 127.0.0.2 — loopback, no listener here }

var
  mock, pid, pr, status, rc, count, i: Integer;
  qrecv: array[0..511] of Byte;
  resp: array[0..60] of Byte;
  fromA, boundA: LongWord;
  fromP, boundP: Integer;
  ns, ips: TDnsIpv4Array;
  n: Int64;

begin
  for i := 0 to 60 do resp[i] := 0;
  resp[2] := $81; resp[3] := $80;
  resp[5] := 1; resp[7] := 2;
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
  pr := PalSetSocketReuseAddr(mock, 1);
  pr := PalBindIpv4(mock, PAL_NET_IP_LOOPBACK, 0);
  boundA := 0; boundP := 0;
  pr := PalGetSockNameIpv4(mock, boundA, boundP);

  pid := PalVfork;
  if pid = 0 then
  begin
    { Only the 127.0.0.1 query reaches the mock; the 127.0.0.2 one is dropped. }
    pr := PalPoll(mock, PAL_POLL_IN, 3000);
    if pr > 0 then
    begin
      fromA := 0; fromP := 0;
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

  ns[0] := IP_LOOPBACK2;          { dead }
  ns[1] := PAL_NET_IP_LOOPBACK;   { mock }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsResolveAList(ns, 2, boundP, 'example.com', ips, count, 400);
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);

  writeln('rcode=', rc);
  writeln('count=', count);
  if (ips[0] = LongWord($5DB8D822)) and (ips[1] = LongWord($5DB8D823)) then
    writeln('multins=ok')
  else
    writeln('multins=bad');
end.
