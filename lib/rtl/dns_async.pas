{ SPDX-License-Identifier: Zlib }
unit dns_async;
{ Async DNS resolution over the coroutine reactor (feature-own-net-http-lib).
  Same wire format as the blocking resolver (dns_wire_core builds/parses), but the
  UDP query yields the coroutine on the reactor instead of blocking the thread —
  so HttpGetAsync can take hostnames. Call from inside a coroutine; drive with
  RunUntilDone.

  resolv.conf / hosts are read synchronously (small local files, no async file
  I/O); only the network round-trip is async. IPv4 A records only; on a truncated
  (TC) response we do not yet retry over TCP (a later slice). }

interface

uses scheduler, platform, dns, dns_config, dns_wire_core, dns_wire_blocking;

{ Async A-record query to an explicit nameserver (host byte order) + port.
  Returns the DNS RCODE (0 = NOERROR, ips[0..count-1] filled), or a negative
  DNS_ERR_* / transport error. Public so a loopback DNS server can test it. }
function DnsQueryAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;

{ Full async resolve: dotted-quad shortcut, then /etc/hosts, then the first
  configured nameserver. Mirror of dns.DnsResolveHost but reactor-driven. }
function DnsResolveHostAsync(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;

implementation

function DnsQueryAAsync(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  sock, qlen, rcode, outId, qid, rc: Integer;
  n: Int64;
  qbuf: array[0..511] of Byte;
  rbuf: array[0..1535] of Byte;
  fromAddr: LongWord;
  fromPort: Integer;
begin
  count := 0;
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if sock < 0 then begin Result := sock; Exit; end;
  rc := PalSetSocketNonBlocking(sock, 1);

  qid := NextQueryId;
  qlen := DnsBuildQueryA(name, qid, @qbuf[0], 512);
  if qlen <= 0 then begin rc := PalSocketClose(sock); Result := qlen; Exit; end;

  if PalSendToIpv4(sock, @qbuf[0], qlen, nsHost, nsPort) < 0 then
  begin rc := PalSocketClose(sock); Result := DNS_ERR_SHORT; Exit; end;

  { Park on the reactor until the datagram is readable; tolerate a spurious wake. }
  WaitReadable(sock);
  n := PalRecvFromIpv4(sock, @rbuf[0], 1536, fromAddr, fromPort);
  while n = PAL_NET_EAGAIN do
  begin
    WaitReadable(sock);
    n := PalRecvFromIpv4(sock, @rbuf[0], 1536, fromAddr, fromPort);
  end;
  rc := PalSocketClose(sock);
  if n <= 0 then begin Result := DNS_ERR_SHORT; Exit; end;

  outId := 0;
  rcode := DnsParseResponseA(@rbuf[0], Integer(n), ips, count, outId);
  if rcode < 0 then begin count := 0; Result := rcode; Exit; end;
  if outId <> qid then begin count := 0; Result := DNS_ERR_BADID; Exit; end;
  Result := rcode;
end;

function DnsResolveHostAsync(const name: string; var ips: TDnsIpv4Array; var count: Integer): Integer;
var
  hostsText, resolvText: string;
  ns: TDnsIpv4Array;
  nsCount, rc: Integer;
  hostIp, ip: LongWord;
begin
  count := 0;

  { dotted-quad needs no network. }
  if DnsParseIpv4(name, 1, Length(name), ip) then
  begin ips[0] := ip; count := 1; Result := 0; Exit; end;

  { "files" first — an /etc/hosts entry wins. }
  rc := ReadFileText(PChar('/etc/hosts'), hostsText, 65536);
  hostIp := 0;
  if DnsLookupHosts(hostsText, name, hostIp) then
  begin ips[0] := hostIp; count := 1; Result := 0; Exit; end;

  { "dns" — first configured nameserver, async. }
  rc := ReadFileText(PChar('/etc/resolv.conf'), resolvText, 8192);
  nsCount := 0;
  rc := DnsParseResolvConf(resolvText, ns, nsCount);
  if nsCount = 0 then begin Result := DNS_ERR_NOCONFIG; Exit; end;

  Result := DnsQueryAAsync(ns[0], DNS_PORT, name, ips, count);
end;

end.
