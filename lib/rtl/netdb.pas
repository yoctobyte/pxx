{ SPDX-License-Identifier: Zlib }
unit netdb;
{ Minimal FPC-compatible NetDB shim (feature-synapse-compile-check), grown to
  the surface Synapse's ssfpc.inc consumes. Resolution rides our own resolver
  (lib/rtl/dns — "files dns" order, /etc/hosts then /etc/resolv.conf
  nameservers); protocols are a static table; services parse /etc/services via
  dns.DnsResolveService.

  Byte-order contract mirrors FPC's quirky netdb: THostEntry.Addr is HOST
  order (callers do HostToNet before storing into a sockaddr), while
  ResolveName/ResolveName6 fill NETWORK-order addresses. TServiceEntry.Port is
  NETWORK order (callers ntohs it). Reverse lookups (ResolveAddress*) are not
  wired yet and return 0 — Synapse then falls back to the literal IP.

  NOT a port of FPC's netdb. }

interface

uses sockets, dns, dns_wire_core;

type
  THostAddr = in_addr;

  THostEntry = record
    Name: string;
    Addr: THostAddr;      { HOST byte order (FPC semantics) }
    Aliases: string;
  end;

  TProtocolEntry = record
    Name: string;
    Number: Integer;
    Aliases: string;
  end;

  TServiceEntry = record
    Name: string;
    Protocol: string;
    Port: Word;           { NETWORK byte order (FPC semantics) }
    Aliases: string;
  end;

function GetHostByName(HostName: string; var H: THostEntry): Boolean;
function ResolveName(HostName: string; var Addresses: array of THostAddr): Integer;
function ResolveName6(HostName: string; var Addresses: array of Tin6_addr): Integer;
function ResolveAddress(Address: THostAddr; var Names: array of string): Integer;
function ResolveAddress6(const Address: Tin6_addr; var Names: array of string): Integer;
function GetProtocolByNumber(proto: Integer; var E: TProtocolEntry): Boolean;
function GetServiceByName(const AName, AProto: string; var E: TServiceEntry): Boolean;

implementation

function GetHostByName(HostName: string; var H: THostEntry): Boolean;
var
  ips: TDnsIpv4Array;
  count: Integer;
begin
  Result := False;
  if DnsResolveHost(HostName, ips, count) <> 0 then Exit;
  if count <= 0 then Exit;
  H.Name := HostName;
  H.Addr.s_addr := ips[0];   { resolver returns host order }
  H.Aliases := '';
  Result := True;
end;

function ResolveName(HostName: string; var Addresses: array of THostAddr): Integer;
var
  ips: TDnsIpv4Array;
  count, i: Integer;
begin
  Result := 0;
  if DnsResolveHost(HostName, ips, count) <> 0 then Exit;
  if count > Length(Addresses) then count := Length(Addresses);
  for i := 0 to count - 1 do
    Addresses[i].s_addr := htonl(ips[i]);   { network order out }
  Result := count;
end;

function ResolveName6(HostName: string; var Addresses: array of Tin6_addr): Integer;
var
  ips: TDnsIpv6Array;
  count, i, j: Integer;
begin
  Result := 0;
  if DnsResolveHost6(HostName, ips, count) <> 0 then Exit;
  if count > Length(Addresses) then count := Length(Addresses);
  for i := 0 to count - 1 do
    for j := 0 to 15 do
      Addresses[i].u6_addr8[j] := ips[i][j];
  Result := count;
end;

function ResolveAddress(Address: THostAddr; var Names: array of string): Integer;
begin
  { PTR lookups not wired yet (see unit note). }
  Result := 0;
end;

function ResolveAddress6(const Address: Tin6_addr; var Names: array of string): Integer;
begin
  Result := 0;
end;

function GetProtocolByNumber(proto: Integer; var E: TProtocolEntry): Boolean;
begin
  Result := True;
  E.Number := proto;
  E.Aliases := '';
  case proto of
    1:  E.Name := 'icmp';
    6:  E.Name := 'tcp';
    17: E.Name := 'udp';
    58: E.Name := 'ipv6-icmp';
  else
    begin
      E.Name := '';
      Result := False;
    end;
  end;
end;

function GetServiceByName(const AName, AProto: string; var E: TServiceEntry): Boolean;
var
  port: Integer;
begin
  Result := False;
  if DnsResolveService(AName, AProto, port) <> 0 then Exit;
  E.Name := AName;
  E.Protocol := AProto;
  E.Port := htons(Word(port));
  E.Aliases := '';
  Result := True;
end;

end.
