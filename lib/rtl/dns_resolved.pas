{ SPDX-License-Identifier: Zlib }
unit dns_resolved;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ systemd-resolved backend for the `dns` facade (feature-dns-backends-selection,
  item 2). Selected with -dPXX_DNS_RESOLVED; without it nothing here is reached
  and `dns_wire` remains the zero-dependency default.

  WHY THIS EXISTS: `dns_wire` talks to the nameservers in /etc/resolv.conf. On a
  systemd-resolved host that file is the 127.0.0.53 stub, which flattens away
  the thing the ticket wants — split DNS. resolved knows which routing domains
  belong to which link, so a VPN's internal names resolve over the VPN's
  nameserver and nothing else leaks to the public one. Asking resolved directly
  is the only way to get that policy; re-implementing it is not on the table.

  PROTOCOL — Varlink, not D-Bus. The ticket estimated "AF_UNIX in PAL + a
  minimal D-Bus client. Sizable". resolved also exposes a Varlink interface at
  /run/systemd/resolve/io.systemd.Resolve, and Varlink is a NUL-terminated JSON
  request and a NUL-terminated JSON reply on a stream socket — no binary
  marshalling, no type signatures, no auth handshake, no bus daemon in the path.
  The socket is world-readable/writable (srw-rw-rw-), so no privilege is needed
  either. That turns a sizable subsystem into this unit, and it is why the
  D-Bus route was not taken. The trade is that Varlink support is a
  systemd-newer-than-v243 thing; a host that lacks the socket falls back, which
  is exactly what a missing D-Bus service would have done too.

  Request:
    {"method":"io.systemd.Resolve.ResolveHostname",
     "parameters":{"name":"<host>","family":<2|10>}}
  Success reply carries `parameters.addresses`, each `{ifindex, family,
  address:[bytes]}` — 4 bytes for AF_INET, 16 for AF_INET6, already in network
  order, which is exactly the shape TDnsIpv4Array/TDnsIpv6Array want.
  A lookup failure is `{"error":"io.systemd.Resolve.DNSError",
  "parameters":{"rcode":N}}`, N being the DNS RCODE, so it maps straight onto
  what the wire path already returns. }

interface

uses platform, dns_wire_core, json, sysutils;

const
  { The well-known Varlink endpoint. A host without systemd-resolved simply has
    no such socket and the connect fails — reported, never worked around. }
  DNS_RESOLVED_SOCKET = '/run/systemd/resolve/io.systemd.Resolve';

  DNS_ERR_RESOLVED_UNAVAIL = -20;  { no socket / connect refused / short reply }
  DNS_ERR_RESOLVED_PROTO   = -21;  { a reply that is not the shape documented above }

{ True when the endpoint is reachable — a cheap connect/close, so a caller (or a
  test) can tell "resolved is not here" from "resolved said no". }
function DnsResolvedAvailable: Boolean;

{ A records via systemd-resolved. Returns 0 with ips/count filled, a positive
  DNS RCODE when resolved reports a lookup failure (3 = NXDOMAIN), or a negative
  DNS_ERR_*. }
function DnsResolvedResolveHost(const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;

{ AAAA sibling. }
function DnsResolvedResolveHost6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer): Integer;

implementation

const
  VARLINK_AF_INET  = 2;
  VARLINK_AF_INET6 = 10;

{ JSON string escaping for the one field we interpolate. A hostname should never
  contain these, which is the reason to escape rather than to trust: a name that
  does would otherwise change the SHAPE of the request instead of being rejected
  by resolved as the bad name it is. }
function JsonEscape(const s: string): string;
var i: Integer; c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c = '"') or (c = '\') then Result := Result + '\' + c
    else if c < ' ' then Result := Result + ' '
    else Result := Result + c;
  end;
end;

{ One Varlink round trip: connect, send `req` + NUL, read to the NUL. Returns
  the reply without its terminator, or '' with a negative code in err. }
function VarlinkCall(const req: string; var err: Integer): string;
var sock, n, i: Integer; msg, acc: string; buf: array[0..8191] of Char;
    sawNul: Boolean;
begin
  err := 0;
  Result := '';
  sock := PalSocket(PAL_NET_AF_UNIX, PAL_NET_SOCK_STREAM, 0);
  if sock < 0 then begin err := DNS_ERR_RESOLVED_UNAVAIL; Exit; end;
  if PalConnectUnix(sock, DNS_RESOLVED_SOCKET) < 0 then
  begin
    PalSocketClose(sock);
    err := DNS_ERR_RESOLVED_UNAVAIL;
    Exit;
  end;
  msg := req + #0;
  if PalSend(sock, @msg[1], Length(msg)) < 0 then
  begin
    PalSocketClose(sock);
    err := DNS_ERR_RESOLVED_UNAVAIL;
    Exit;
  end;
  { Varlink frames on the NUL, so read until one arrives rather than assuming a
    reply fits in a single recv. }
  acc := '';
  sawNul := False;
  while not sawNul do
  begin
    n := PalRecv(sock, @buf[0], SizeOf(buf));
    if n <= 0 then break;
    for i := 0 to n - 1 do
      if buf[i] = #0 then sawNul := True
      else if not sawNul then acc := acc + buf[i];
  end;
  PalSocketClose(sock);
  if not sawNul then begin err := DNS_ERR_RESOLVED_UNAVAIL; Exit; end;
  Result := acc;
end;

function DnsResolvedAvailable: Boolean;
var sock: Integer;
begin
  Result := False;
  sock := PalSocket(PAL_NET_AF_UNIX, PAL_NET_SOCK_STREAM, 0);
  if sock < 0 then Exit;
  Result := PalConnectUnix(sock, DNS_RESOLVED_SOCKET) >= 0;
  PalSocketClose(sock);
end;

{ Shared request/parse. `family` selects A or AAAA; the caller's collector is
  handed each address element that matches. Returns 0, a positive RCODE, or a
  negative DNS_ERR_*, and leaves the parsed `addresses` array in `addrs` (nil
  when the result is not 0). The root value is returned too so the caller can
  free the whole tree exactly once. }
function ResolveInto(const name: string; family: Integer;
                     var root: TJSONValue; var addrs: TJSONValue): Integer;
var req, reply: string; err: Integer; params, e: TJSONValue;
begin
  root := nil;
  addrs := nil;
  if name = '' then begin ResolveInto := DNS_ERR_RESOLVED_PROTO; Exit; end;
  req := '{"method":"io.systemd.Resolve.ResolveHostname","parameters":{"name":"'
         + JsonEscape(name) + '","family":' + IntToStr(family) + '}}';
  reply := VarlinkCall(req, err);
  if err <> 0 then begin ResolveInto := err; Exit; end;

  try
    root := JSONParse(reply);
  except
    root := nil;
  end;
  if root = nil then begin ResolveInto := DNS_ERR_RESOLVED_PROTO; Exit; end;

  { a lookup failure carries the DNS RCODE, which is what the wire path returns }
  e := root.GetValue('error');
  if e <> nil then
  begin
    params := root.GetValue('parameters');
    if params <> nil then
    begin
      e := params.GetValue('rcode');
      if (e <> nil) and (e.Kind = jkInt) then
      begin
        ResolveInto := Integer(e.AsInteger);
        Exit;
      end;
    end;
    { an error without an rcode is still an honest failure, just not a DNS one }
    ResolveInto := DNS_ERR_RESOLVED_UNAVAIL;
    Exit;
  end;

  params := root.GetValue('parameters');
  if params = nil then begin ResolveInto := DNS_ERR_RESOLVED_PROTO; Exit; end;
  addrs := params.GetValue('addresses');
  if (addrs = nil) or (addrs.Kind <> jkArray) then
  begin
    { no addresses at all is NODATA, not an error — zero answers, RCODE 0 }
    addrs := nil;
    ResolveInto := 0;
    Exit;
  end;
  ResolveInto := 0;
end;

{ True when element `el` is an address of `family`, with `bytes` the expected
  length; `arr` is then its byte array. }
function AddrElem(el: TJSONValue; family, bytes: Integer;
                  var arr: TJSONValue): Boolean;
var f: TJSONValue;
begin
  AddrElem := False;
  if (el = nil) or (el.Kind <> jkObject) then Exit;
  f := el.GetValue('family');
  if (f = nil) or (f.Kind <> jkInt) or (Integer(f.AsInteger) <> family) then Exit;
  arr := el.GetValue('address');
  if (arr = nil) or (arr.Kind <> jkArray) or (arr.Count <> bytes) then Exit;
  AddrElem := True;
end;

function DnsResolvedResolveHost(const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;
var root, addrs, el, arr: TJSONValue; i, rc: Integer; v: LongWord;
begin
  count := 0;
  rc := ResolveInto(name, VARLINK_AF_INET, root, addrs);
  if rc <> 0 then
  begin
    if root <> nil then root.Free;
    DnsResolvedResolveHost := rc;
    Exit;
  end;
  if addrs <> nil then
    for i := 0 to addrs.Count - 1 do
    begin
      if count >= DNS_MAX_IPS then break;
      el := addrs.GetItem(i);
      if AddrElem(el, VARLINK_AF_INET, 4, arr) then
      begin
        { the four bytes are network order; TDnsIpv4Array holds host order,
          which is what the wire path's callers already expect }
        v := (LongWord(arr.GetItem(0).AsInteger) shl 24)
          or (LongWord(arr.GetItem(1).AsInteger) shl 16)
          or (LongWord(arr.GetItem(2).AsInteger) shl 8)
          or  LongWord(arr.GetItem(3).AsInteger);
        ips[count] := v;
        count := count + 1;
      end;
    end;
  if root <> nil then root.Free;
  DnsResolvedResolveHost := 0;
end;

function DnsResolvedResolveHost6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer): Integer;
var root, addrs, el, arr: TJSONValue; i, j, rc: Integer;
begin
  count := 0;
  rc := ResolveInto(name, VARLINK_AF_INET6, root, addrs);
  if rc <> 0 then
  begin
    if root <> nil then root.Free;
    DnsResolvedResolveHost6 := rc;
    Exit;
  end;
  if addrs <> nil then
    for i := 0 to addrs.Count - 1 do
    begin
      if count >= DNS_MAX_IPS then break;
      el := addrs.GetItem(i);
      if AddrElem(el, VARLINK_AF_INET6, 16, arr) then
      begin
        { AAAA bytes are already network order, which is how TDnsIpv6 stores
          them — no swap, unlike the IPv4 case above }
        for j := 0 to 15 do
          ips[count][j] := Byte(arr.GetItem(j).AsInteger);
        count := count + 1;
      end;
    end;
  if root <> nil then root.Free;
  DnsResolvedResolveHost6 := 0;
end;

end.
