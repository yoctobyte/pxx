{ SPDX-License-Identifier: Zlib }
unit netconnect;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Connect to a HOST NAME — the piece that sits above both the transport and the
  resolver (feature-net-a-first-connect-by-name).

  WHY ITS OWN UNIT. `net.pas` deliberately `uses platform` and nothing else, and
  `dns.pas` does not know about sockets. That separation is explicit in
  feature-networking's design: the transport must not depend on the resolver.
  Putting a name-resolving connect in either one would break it in one direction
  or the other, so the policy lives here, above both. This unit is the only
  place in the tree that depends on `net` AND `dns` together.

  ORDERING POLICY — A first, then AAAA, decided by the user 2026-08-01 in
  decide-ipv6-dualstack-and-aaaa-ordering, against that ticket's own
  recommendation:

    "the timeout-on-first-try risk is symmetric regardless of which family goes
    first, and IPv4 connectivity remains the more reliably-working leg in
    practice (CGNAT still connects; broken/absent v6 routing is still the more
    common failure mode). Leading with v4 is the safer default on reliability
    grounds alone."

  **No Happy Eyeballs**, also decided, and not merely unimplemented: the
  concurrency it needs buys nothing without a v6-adoption goal this project does
  not have. `asyncnet` has the reactor that would make it natural — that is
  precisely the temptation the decision declined, so do not add it here without
  reopening that ticket.

  An IP literal resolves to itself without network on both families (see
  bug-b-dns-wire-ipv4-literal-returns-nxdomain), so a caller may pass an address
  or a name interchangeably. }

interface

uses platform, net, dns, dns_wire_core, platform_types;

const
  { Nothing resolved at all — distinct from "resolved but every address
    refused", which returns the last connect error so the caller sees the real
    errno (ECONNREFUSED, ETIMEDOUT, ...) rather than a generic failure. }
  NETCONNECT_ERR_NORESOLVE = -30;

  NETCONNECT_DEFAULT_TIMEOUT_MS = 10000;

{ Connect to `host` (a name or an IP literal) on `port`. Tries every A address
  in order, then every AAAA address. Returns a connected blocking socket >= 0,
  the LAST connect error if addresses were found but none accepted, or
  NETCONNECT_ERR_NORESOLVE if neither family resolved. }
function NetConnectHost(const host: string; port: Integer): TNetSocket;
function NetConnectHostTimeout(const host: string; port, timeoutMs: Integer): TNetSocket;

{ Same, and reports which address actually connected. `used.Family` is how a
  caller (or a test) can tell WHICH family won, which is the only way to observe
  the ordering policy — "it connected" is true under either order. }
function NetConnectHostEx(const host: string; port, timeoutMs: Integer;
                          var used: TNetAddress): TNetSocket;

implementation

function NetConnectHostEx(const host: string; port, timeoutMs: Integer;
                          var used: TNetAddress): TNetSocket;
var
  ips: TDnsIpv4Array;
  ip6: TDnsIpv6Array;
  a: TNetAddress;
  pal6: TPalIn6Addr;
  n, i, j, rc, sock, lastErr: Integer;
  tried: Boolean;
begin
  used := NetAddress(0, 0);
  lastErr := NETCONNECT_ERR_NORESOLVE;
  tried := False;

  { ---- A first, per the decision ---- }
  n := 0;
  rc := DnsResolveHost(host, ips, n);
  if rc = 0 then
    for i := 0 to n - 1 do
    begin
      a := NetAddress(ips[i], port);
      sock := NetTcpConnectTimeout(a, timeoutMs);
      tried := True;
      if sock >= 0 then
      begin
        used := a;
        NetConnectHostEx := sock;
        Exit;
      end;
      lastErr := sock;
    end;

  { ---- then AAAA, as the fallback ---- }
  n := 0;
  rc := DnsResolveHost6(host, ip6, n);
  if rc = 0 then
    for i := 0 to n - 1 do
    begin
      for j := 0 to 15 do pal6.Bytes[j] := ip6[i][j];
      { scope id 0: a link-local target needs an interface index the resolver
        does not carry, so those are out of reach here rather than silently
        connected to the wrong interface }
      a := NetAddress6(pal6, port, 0);
      sock := NetTcpConnectTimeout(a, timeoutMs);
      tried := True;
      if sock >= 0 then
      begin
        used := a;
        NetConnectHostEx := sock;
        Exit;
      end;
      lastErr := sock;
    end;

  if not tried then NetConnectHostEx := NETCONNECT_ERR_NORESOLVE
  else NetConnectHostEx := lastErr;
end;

function NetConnectHostTimeout(const host: string; port, timeoutMs: Integer): TNetSocket;
var used: TNetAddress;
begin
  NetConnectHostTimeout := NetConnectHostEx(host, port, timeoutMs, used);
end;

function NetConnectHost(const host: string; port: Integer): TNetSocket;
var used: TNetAddress;
begin
  NetConnectHost := NetConnectHostEx(host, port, NETCONNECT_DEFAULT_TIMEOUT_MS, used);
end;

end.
