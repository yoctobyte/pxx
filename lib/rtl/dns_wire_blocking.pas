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

{ Resolve A records for `name` by querying nameserver (host byte order ipv4) on
  nsPort over UDP, waiting up to timeoutMs. Returns the DNS RCODE (0 = NOERROR)
  with ips[0..count-1] filled (host byte order), or a negative error: a PAL
  socket errno, PAL_NET_ETIMEDOUT, or a DNS_ERR_* (malformed / bad id). }
function DnsResolveA(nsHost: LongWord; nsPort: Integer; const name: string;
  var ips: TDnsIpv4Array; var count: Integer; timeoutMs: Integer): Integer;

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
  qlen := DnsBuildQueryA(name, queryId, @qbuf[0]);
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

end.
