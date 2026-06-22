program lib_dns_tcp;
{ TCP fallback on a truncated (TC) DNS answer. The forked mock serves the UDP
  query with a header that only sets the TC bit (no answers), then accepts a TCP
  connection on the same port and serves the full length-prefixed response.
  DnsResolveA must detect TC, retry over TCP, and return the addresses. }

uses platform, dns_wire_core, dns_wire_blocking;

var
  udp, tcpl, pid, pr, status, rc, count, i, acc, qn: Integer;
  q: array[0..511] of Byte;
  tcpbuf: array[0..599] of Byte;
  tc: array[0..11] of Byte;
  resp: array[0..60] of Byte;
  lp: array[0..1] of Byte;
  fromA, aA, boundA: LongWord;
  fromP, aP, boundP: Integer;
  ips: TDnsIpv4Array;
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

  { UDP socket (ephemeral port), then a TCP listener on the same port. }
  udp := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  pr := PalSetSocketReuseAddr(udp, 1);
  pr := PalBindIpv4(udp, PAL_NET_IP_LOOPBACK, 0);
  boundA := 0; boundP := 0;
  pr := PalGetSockNameIpv4(udp, boundA, boundP);

  tcpl := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  pr := PalSetSocketReuseAddr(tcpl, 1);
  pr := PalBindIpv4(tcpl, PAL_NET_IP_LOOPBACK, boundP);
  pr := PalListen(tcpl, 4);

  pid := PalVfork;
  if pid = 0 then
  begin
    { UDP: reply with TC bit set (QR|TC|RD, RA), no answers. }
    pr := PalPoll(udp, PAL_POLL_IN, 3000);
    if pr > 0 then
    begin
      fromA := 0; fromP := 0;
      n := PalRecvFromIpv4(udp, @q[0], 512, fromA, fromP);
      for i := 0 to 11 do tc[i] := 0;
      tc[0] := q[0]; tc[1] := q[1];
      tc[2] := $83; tc[3] := $80;
      n := PalSendToIpv4(udp, @tc[0], 12, fromA, fromP);
    end;
    { TCP: accept and serve the full length-prefixed response. }
    pr := PalPoll(tcpl, PAL_POLL_IN, 3000);
    if pr > 0 then
    begin
      aA := 0; aP := 0;
      acc := PalAcceptIpv4(tcpl, aA, aP);
      if acc >= 0 then
      begin
        { Read until we have at least the 2-byte length + 2-byte id (the two
          client sends may arrive as separate TCP segments). }
        qn := 0;
        while qn < 4 do
        begin
          pr := PalPoll(acc, PAL_POLL_IN, 3000);
          if pr <= 0 then qn := 999;
          if qn < 4 then
          begin
            n := PalRecv(acc, @tcpbuf[qn], 600 - qn);
            if n <= 0 then qn := 999 else qn := qn + Integer(n);
          end;
        end;
        if qn < 900 then
        begin
          { echo the query id (stream: [len_hi][len_lo][id_hi][id_lo]...) }
          resp[0] := tcpbuf[2];
          resp[1] := tcpbuf[3];
          lp[0] := 0; lp[1] := 61;
          n := PalSend(acc, @lp[0], 2);
          n := PalSend(acc, @resp[0], 61);
        end;
        pr := PalSocketClose(acc);
      end;
    end;
    Halt(0);
  end;

  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsResolveA(PAL_NET_IP_LOOPBACK, boundP, 'example.com', ips, count, 2000);
  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(tcpl);
  pr := PalSocketClose(udp);

  writeln('rcode=', rc);
  writeln('count=', count);
  if (ips[0] = LongWord($5DB8D822)) and (ips[1] = LongWord($5DB8D823)) then
    writeln('tcp-fallback=ok')
  else
    writeln('tcp-fallback=bad');
end.
