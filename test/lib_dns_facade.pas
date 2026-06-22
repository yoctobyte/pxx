program lib_dns_facade;
{ Test the dns.pas resolver facade seam DnsResolveHostEx: an /etc/hosts match
  short-circuits (no query), and a miss falls through to a UDP query. A forked
  mock DNS server serves the one wire query (process, timeout-bounded). }

uses platform, dns_wire_core, dns;

var
  mock, pid, pr, status, rc, count, i: Integer;
  qrecv: array[0..511] of Byte;
  resp: array[0..60] of Byte;
  fromA, boundA: LongWord;
  fromP, boundP: Integer;
  ips: TDnsIpv4Array;
  hosts: string;
  n: Int64;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

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

  hosts := '192.168.1.10  myhost.local myhost';

  mock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  pr := PalSetSocketReuseAddr(mock, 1);
  pr := PalBindIpv4(mock, PAL_NET_IP_LOOPBACK, 0);
  boundA := 0; boundP := 0;
  pr := PalGetSockNameIpv4(mock, boundA, boundP);

  pid := PalVfork;
  if pid = 0 then
  begin
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

  { hosts hit: resolves from the hosts text, mock not contacted. }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsResolveHostEx(hosts, PAL_NET_IP_LOOPBACK, boundP, 'myhost', ips, count, 2000);
  Show('hosts-hit', (rc = 0) and (count = 1) and (ips[0] = LongWord($C0A8010A)));

  { hosts miss: falls through to the UDP query served by the mock. }
  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsResolveHostEx(hosts, PAL_NET_IP_LOOPBACK, boundP, 'example.com', ips, count, 2000);
  writeln('wire-rcode=', rc);
  writeln('wire-count=', count);
  Show('wire-ip0', ips[0] = LongWord($5DB8D822));

  pr := PalWait4(pid, @status, 0, nil);
  pr := PalSocketClose(mock);
end.
