{ SPDX-License-Identifier: Zlib }
unit dns_libc;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ getaddrinfo backend for the `dns` facade (feature-dns-libc-backend). Selected
  with -dPXX_DNS_LIBC; without it nothing here is reached and `dns_wire` remains
  the zero-dependency default.

  WHY THIS EXISTS ALONGSIDE dns_resolved. The two backends' gaps are disjoint,
  which is why decide-dns-libc-backend-shape kept both. `dns_resolved` needs
  systemd + resolved running; this one needs glibc at run time. What only this
  one reaches is **nsswitch policy**: custom NSS modules, mDNS (`.local`), LDAP
  or VPN name services wired through /etc/nsswitch.conf. `dns_resolved` cannot
  see any of that, and `dns_wire` sees none of it by construction, because both
  speak DNS while nsswitch is a layer above DNS.

  THE COST, STATED PLAINLY. This is the one backend that makes the binary depend
  on glibc at run time, so it is opt-in twice over: it needs BOTH -dPXX_DNS_LIBC
  and -dPXX_DYNLIB_LIBC (the loader is itself opt-in, keeping the syscall-only
  core libc-free). `dns.pas` makes the missing loader a compile-time error
  rather than a build that silently always falls back.

  ABI, NOT API. getaddrinfo hands back a linked list of `struct addrinfo`, and
  every field is read by OFFSET. Those offsets are pinned in
  `test/lib_dns_libc.pas` against values taken from a gcc `offsetof` probe on
  this ABI, rather than copied from documentation —
  note glibc orders `ai_addr` BEFORE `ai_canonname`, the reverse of how POSIX
  reference pages commonly list them, and getting that backwards yields a
  plausible wrong pointer rather than a failure. The record below reproduces
  glibc's layout under pxx's natural alignment; verified identical to gcc on
  x86-64 and to the expected 32-bit layout on i386/arm32. }

interface

uses platform, dynlibs, dns_wire_core;

const
  DNS_ERR_LIBC_UNAVAIL = -22;  { no loader, no libc, or getaddrinfo unresolved }

{ glibc's `struct addrinfo`, exposed so a test can assert its LAYOUT — the
  offsets are the ABI contract this backend depends on, and a wrong one yields
  a plausible wrong address rather than a failure. Pinned against gcc in
  test/lib_dns_libc.pas. Note ai_addr precedes ai_canonname: that is glibc's
  order, the reverse of how POSIX reference pages commonly list them. }
type
  TCAddrInfo = record
    ai_flags: Integer;
    ai_family: Integer;
    ai_socktype: Integer;
    ai_protocol: Integer;
    ai_addrlen: LongWord;
    ai_addr: Pointer;        { -> sockaddr_in / sockaddr_in6 }
    ai_canonname: Pointer;
    ai_next: Pointer;        { -> TCAddrInfo }
  end;
  PCAddrInfo = ^TCAddrInfo;

{ True when libc is loaded and getaddrinfo resolved — so a caller (or a test)
  can tell "no glibc here" from "glibc said no". }
function DnsLibcAvailable: Boolean;

{ A records via getaddrinfo. Returns 0 with ips/count filled, a positive DNS
  RCODE for a lookup failure (3 = NXDOMAIN), or a negative DNS_ERR_*. }
function DnsLibcResolveHost(const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;

{ AAAA sibling. }
function DnsLibcResolveHost6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer): Integer;

implementation

const
  LIBC_SONAME = 'libc.so.6';

  AF_UNSPEC_C = 0;
  AF_INET_C   = 2;
  AF_INET6_C  = 10;
  SOCK_STREAM_C = 1;

  { getaddrinfo's own error codes (glibc values, from the oracle) }
  EAI_NONAME = -2;
  EAI_AGAIN  = -3;
  EAI_FAIL   = -4;
  EAI_NODATA = -5;

type
  PByteArr = ^Byte;

  TGetAddrInfo  = function(node, service, hints: Pointer; res: Pointer): Integer; cdecl;
  TFreeAddrInfo = procedure(res: Pointer); cdecl;

var
  LibcTried: Boolean;
  LibcHandle: TLibHandle;
  FnGetAddrInfo: TGetAddrInfo;
  FnFreeAddrInfo: TFreeAddrInfo;

{ Load libc and resolve the two entry points once. A failure at any step leaves
  the pointers nil, which every caller checks — the backend reports itself
  unavailable and the facade falls back, rather than half-working. }
procedure LibcInit;
begin
  if LibcTried then Exit;
  LibcTried := True;
  FnGetAddrInfo := nil;
  FnFreeAddrInfo := nil;
  if not PalHasDynlib then Exit;
  LibcHandle := LoadLibrary(LIBC_SONAME);
  if LibcHandle = NilHandle then Exit;
  FnGetAddrInfo := TGetAddrInfo(GetProcedureAddress(LibcHandle, 'getaddrinfo'));
  FnFreeAddrInfo := TFreeAddrInfo(GetProcedureAddress(LibcHandle, 'freeaddrinfo'));
  if (Pointer(FnGetAddrInfo) = nil) or (Pointer(FnFreeAddrInfo) = nil) then
  begin
    FnGetAddrInfo := nil;
    FnFreeAddrInfo := nil;
  end;
end;

function DnsLibcAvailable: Boolean;
begin
  LibcInit;
  DnsLibcAvailable := Pointer(FnGetAddrInfo) <> nil;
end;

{ getaddrinfo's failures onto DNS RCODEs, so the facade can treat a libc answer
  exactly like a wire answer. NONAME/NODATA are "the name has no such record",
  which is NXDOMAIN's 3; AGAIN and FAIL are server-side, which is SERVFAIL's 2.
  Anything else is not a DNS verdict at all and stays a backend error, so the
  facade falls back instead of reporting a lookup result we did not get. }
function EaiToRcode(e: Integer): Integer;
begin
  if (e = EAI_NONAME) or (e = EAI_NODATA) then EaiToRcode := 3
  else if (e = EAI_AGAIN) or (e = EAI_FAIL) then EaiToRcode := 2
  else EaiToRcode := DNS_ERR_LIBC_UNAVAIL;
end;

{ One getaddrinfo call for `family`. On success `res` holds the list head and
  the caller must hand it to FnFreeAddrInfo. }
function Lookup(const name: string; family: Integer; var res: Pointer): Integer;
var hints: TCAddrInfo; cname: array[0..255] of Char; i, rc: Integer;
begin
  res := nil;
  LibcInit;
  if Pointer(FnGetAddrInfo) = nil then begin Lookup := DNS_ERR_LIBC_UNAVAIL; Exit; end;
  if (name = '') or (Length(name) > 254) then
  begin
    Lookup := DNS_ERR_LIBC_UNAVAIL;
    Exit;
  end;
  for i := 1 to Length(name) do cname[i - 1] := name[i];
  cname[Length(name)] := #0;

  hints.ai_flags := 0;
  hints.ai_family := family;
  hints.ai_socktype := SOCK_STREAM_C;   { without this every address is
                                          returned once per socket type }
  hints.ai_protocol := 0;
  hints.ai_addrlen := 0;
  hints.ai_addr := nil;
  hints.ai_canonname := nil;
  hints.ai_next := nil;

  rc := FnGetAddrInfo(@cname[0], nil, @hints, @res);
  if rc <> 0 then
  begin
    res := nil;
    Lookup := EaiToRcode(rc);
    Exit;
  end;
  Lookup := 0;
end;

function DnsLibcResolveHost(const name: string;
  var ips: TDnsIpv4Array; var count: Integer): Integer;
var res, cur: Pointer; ai: PCAddrInfo; sa: PByteArr; rc: Integer; v: LongWord;
begin
  count := 0;
  rc := Lookup(name, AF_INET_C, res);
  if rc <> 0 then begin DnsLibcResolveHost := rc; Exit; end;
  cur := res;
  while (cur <> nil) and (count < DNS_MAX_IPS) do
  begin
    ai := PCAddrInfo(cur);
    if (ai^.ai_family = AF_INET_C) and (ai^.ai_addr <> nil) then
    begin
      { sockaddr_in: sin_addr is 4 bytes at offset 4, network order }
      sa := PByteArr(Pointer(Int64(ai^.ai_addr) + 4));
      v := (LongWord(PByteArr(Pointer(Int64(sa) + 0))^) shl 24)
        or (LongWord(PByteArr(Pointer(Int64(sa) + 1))^) shl 16)
        or (LongWord(PByteArr(Pointer(Int64(sa) + 2))^) shl 8)
        or  LongWord(PByteArr(Pointer(Int64(sa) + 3))^);
      ips[count] := v;
      count := count + 1;
    end;
    cur := ai^.ai_next;
  end;
  if res <> nil then FnFreeAddrInfo(res);
  DnsLibcResolveHost := 0;
end;

function DnsLibcResolveHost6(const name: string;
  var ips: TDnsIpv6Array; var count: Integer): Integer;
var res, cur: Pointer; ai: PCAddrInfo; rc, j: Integer;
begin
  count := 0;
  rc := Lookup(name, AF_INET6_C, res);
  if rc <> 0 then begin DnsLibcResolveHost6 := rc; Exit; end;
  cur := res;
  while (cur <> nil) and (count < DNS_MAX_IPS) do
  begin
    ai := PCAddrInfo(cur);
    if (ai^.ai_family = AF_INET6_C) and (ai^.ai_addr <> nil) then
    begin
      { sockaddr_in6: sin6_addr is 16 bytes at offset 8, already network order
        (no swap, unlike the IPv4 case) }
      for j := 0 to 15 do
        ips[count][j] := PByteArr(Pointer(Int64(ai^.ai_addr) + 8 + j))^;
      count := count + 1;
    end;
    cur := ai^.ai_next;
  end;
  if res <> nil then FnFreeAddrInfo(res);
  DnsLibcResolveHost6 := 0;
end;

end.
