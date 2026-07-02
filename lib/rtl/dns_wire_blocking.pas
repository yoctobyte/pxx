{ SPDX-License-Identifier: Zlib }
unit dns_wire_blocking;
{ Blocking DNS A-record resolver over PAL UDP — ties dns_wire_core (packet
  codec) to the PAL socket surface (feature-dns-resolver-library). One query to
  one nameserver, bounded by a timeout. The caller supplies the nameserver
  address (from dns_config / resolv.conf); this unit holds no resolver policy
  and never assumes a public DNS server.

  First slice: single UDP query, no retry across multiple nameservers, no TCP
  fallback on a truncated (TC) response, no search-domain qualification. Those
  are later slices in the same facade. }

interface

uses platform, dns_wire_core, random;

const
  DNS_PORT = 53;
  DNS_ERR_BADID = -3;   { response transaction id did not match the query }
  DNS_ERR_NONS  = -5;   { nameserver list was empty }

{ Resolve A records for `name` by querying nameserver (host byte order ipv4) on
  nsPort over UDP, waiting up to timeoutMs. Returns the DNS RCODE (0 = NOERROR)
  with ips[0..count-1] filled (host byte order), or a negative error: a PAL
  socket errno, PAL_NET_ETIMEDOUT, or a DNS_ERR_* (malformed / bad id). }
function DnsResolveA(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

{ Try the nameservers ns[0..nsCount-1] in order until one gives a definitive
  answer. A non-negative result (the DNS RCODE, even NXDOMAIN) is definitive and
  returned immediately; a negative transport failure (timeout / refused / bad id)
  moves on to the next nameserver. Returns the last error if all fail, or
  DNS_ERR_NONS if the list is empty. }
function DnsResolveAList(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

implementation

var
  gSeeded: Boolean;   { lazy one-time seed of the query-id generator }

{ A per-query transaction id. Combined with the OS-random source port this is
  the basic off-path spoofing defense — a fixed id is trivially forgeable.
  Seeded from the monotonic clock; not cryptographic (LCG), good enough for the
  id+port entropy budget, to be upgraded to a CSPRNG later. }
function NextQueryId: Integer;
begin
  if not gSeeded then
  begin
    RandSeed(LongWord(PalMonotonicMillis));
    gSeeded := True;
  end;
  NextQueryId := Random(65536);
end;

{ Read exactly `need` bytes from a stream socket, polling for readability up to
  timeoutMs between reads (DNS-over-TCP messages are length-prefixed, and TCP may
  deliver them in pieces). Returns True only if all bytes arrived. }
function RecvN(sock: Integer; buf: Pointer; need, timeoutMs: Integer): Boolean;
var
  got, pr: Integer;
  n: Int64;
begin
  got := 0;
  while got < need do
  begin
    pr := PalPoll(sock, PAL_POLL_IN, timeoutMs);
    if pr <= 0 then
    begin
      RecvN := False;
      Exit;
    end;
    n := PalRecv(sock, Pointer(Int64(buf) + got), need - got);
    if n <= 0 then
    begin
      RecvN := False;
      Exit;
    end;
    got := got + Integer(n);
  end;
  RecvN := True;
end;

{ DNS over TCP: connect, send the 2-byte-length-prefixed query, read the
  2-byte-length-prefixed response into respBuf. Returns the response length
  (capped at respMax), or a negative PAL/timeout error. }
function DnsQueryTcp(nsHost: LongWord; nsPort: Integer; queryBuf: Pointer; qlen: Integer;
  respBuf: Pointer; respMax, timeoutMs: Integer): Integer;
var
  sock: Integer;
  lenpfx: array[0..1] of Byte;
  n: Int64;
  rlen: Integer;
begin
  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if sock < 0 then
  begin
    DnsQueryTcp := sock;
    Exit;
  end;
  if PalConnectIpv4(sock, nsHost, nsPort) < 0 then
  begin
    PalSocketClose(sock);
    DnsQueryTcp := PAL_NET_ECONNREFUSED;
    Exit;
  end;
  lenpfx[0] := (qlen shr 8) and $FF;
  lenpfx[1] := qlen and $FF;
  n := PalSend(sock, @lenpfx[0], 2);
  if (n = 2) then
    n := PalSend(sock, queryBuf, qlen);
  if Integer(n) <> qlen then
  begin
    PalSocketClose(sock);
    DnsQueryTcp := -1;
    Exit;
  end;
  if not RecvN(sock, @lenpfx[0], 2, timeoutMs) then
  begin
    PalSocketClose(sock);
    DnsQueryTcp := PAL_NET_ETIMEDOUT;
    Exit;
  end;
  rlen := (Integer(lenpfx[0]) shl 8) or Integer(lenpfx[1]);
  if rlen > respMax then rlen := respMax;
  if not RecvN(sock, respBuf, rlen, timeoutMs) then
  begin
    PalSocketClose(sock);
    DnsQueryTcp := PAL_NET_ETIMEDOUT;
    Exit;
  end;
  PalSocketClose(sock);
  DnsQueryTcp := rlen;
end;

function DnsResolveA(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;
var
  sock, qlen, pr, i, queryId: Integer;
  qbuf: array[0..511] of Byte;
  rbuf: array[0..1535] of Byte;
  n: Int64;
  localIps: TDnsIpv4Array;
  localCount, outId, rcode: Integer;
  fromAddr: LongWord;
  fromPort: Integer;
begin
  count := 0;
  queryId := NextQueryId;
  qlen := DnsBuildQueryA(name, queryId, @qbuf[0], 512);
  if qlen < 0 then
  begin
    DnsResolveA := qlen;
    Exit;
  end;

  sock := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if sock < 0 then
  begin
    DnsResolveA := sock;
    Exit;
  end;

  n := PalSendToIpv4(sock, @qbuf[0], qlen, nsHost, nsPort);
  if n < 0 then
  begin
    PalSocketClose(sock);
    DnsResolveA := Integer(n);
    Exit;
  end;

  pr := PalPoll(sock, PAL_POLL_IN, timeoutMs);
  if pr <= 0 then
  begin
    PalSocketClose(sock);
    if pr = 0 then DnsResolveA := PAL_NET_ETIMEDOUT else DnsResolveA := pr;
    Exit;
  end;

  fromAddr := 0;
  fromPort := 0;
  n := PalRecvFromIpv4(sock, @rbuf[0], 1536, fromAddr, fromPort);
  PalSocketClose(sock);
  if n < 0 then
  begin
    DnsResolveA := Integer(n);
    Exit;
  end;

  { Truncated (TC) answer: retry the same query over TCP, which has no datagram
    size limit. The query bytes in qbuf are reused. }
  if DnsTruncated(@rbuf[0], Integer(n)) then
  begin
    n := DnsQueryTcp(nsHost, nsPort, @qbuf[0], qlen, @rbuf[0], 1536, timeoutMs);
    if n < 0 then
    begin
      DnsResolveA := Integer(n);
      Exit;
    end;
  end;

  { Parse into locals, then copy out — keeps this riscv32-clean by not forwarding
    a var parameter into another routine's var parameter
    (feature-riscv32-var-param-forwarding). }
  localCount := 0;
  outId := 0;
  rcode := DnsParseResponseA(@rbuf[0], Integer(n), localIps, localCount, outId);
  if rcode < 0 then
  begin
    DnsResolveA := rcode;
    Exit;
  end;
  if outId <> queryId then
  begin
    DnsResolveA := DNS_ERR_BADID;
    Exit;
  end;

  for i := 0 to localCount - 1 do
    ips[i] := localIps[i];
  count := localCount;
  DnsResolveA := rcode;
end;

function DnsResolveAList(const ns: TDnsIpv4Array; nsCount, nsPort: Integer;
  const name: string; var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;
var
  i, j, rc, localCount: Integer;
  localIps: TDnsIpv4Array;
begin
  count := 0;
  if nsCount <= 0 then
  begin
    DnsResolveAList := DNS_ERR_NONS;
    Exit;
  end;
  rc := DNS_ERR_NONS;
  for i := 0 to nsCount - 1 do
  begin
    localCount := 0;
    rc := DnsResolveA(ns[i], nsPort, name, localIps, localCount, timeoutMs);
    if rc >= 0 then
    begin
      { definitive answer (even NXDOMAIN) — copy out and stop }
      for j := 0 to localCount - 1 do
        ips[j] := localIps[j];
      count := localCount;
      DnsResolveAList := rc;
      Exit;
    end;
    { negative = transport failure; try the next nameserver }
  end;
  DnsResolveAList := rc;   { last error }
end;

end.
