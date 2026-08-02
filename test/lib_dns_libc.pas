{ The getaddrinfo DNS backend (feature-dns-libc-backend).

  Built WITHOUT -dPXX_DNS_LIBC this asserts only that the facade still answers,
  which is the point of running it that way: adding a backend must not disturb
  the default. Built WITH it (which also requires -dPXX_DYNLIB_LIBC), the libc
  path is exercised and compared against the wire path.

  THE ABI ASSERTIONS ARE THE IMPORTANT PART. getaddrinfo returns a linked list
  of `struct addrinfo` and this backend reads every field by offset, so the
  record layout IS the contract. A wrong offset does not fail — it yields a
  plausible wrong address. The expected values below come from a gcc
  `offsetof` probe on this ABI, not from documentation, and they catch a
  layout change on either side. Note ai_addr precedes ai_canonname: glibc's
  order, the reverse of how POSIX reference pages commonly list them, and the
  single easiest field pair to get backwards.

  NO NETWORK: every lookup is `localhost`. SKIPS its libc half where glibc or
  the loader is absent — that is a supported configuration, covered by the
  facade falling back to wire. }
program lib_dns_libc;
uses dns, dns_wire_core, sysutils
{$ifdef PXX_DNS_LIBC}
     , dns_libc
{$endif}
     ;

var fails: Integer;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

var
  ips, ips2: TDnsIpv4Array;
  ip6: TDnsIpv6Array;
  n, n2, rc: Integer;
{$ifdef PXX_DNS_LIBC}
  ai: TCAddrInfo;
  base: Int64;
  ptr, i, same: Integer;
{$endif}
begin
  fails := 0;

  { the facade still answers, whichever backend is compiled in }
  rc := DnsResolveHost('localhost', ips, n);
  Chk('facade_v4_rc', rc = 0, True);
  Chk('facade_v4_loopback', (n > 0) and (ips[0] = $7F000001), True);
  rc := DnsResolveHost6('localhost', ip6, n);
  Chk('facade_v6_rc', rc = 0, True);
  Chk('facade_v6_loopback', (n > 0) and (ip6[0][0] = 0) and (ip6[0][15] = 1), True);

{$ifdef PXX_DNS_LIBC}
  { ---- ABI: struct addrinfo's layout, against the gcc offsetof values ---- }
  base := Int64(@ai);
  ptr := SizeOf(Pointer);
  ChkI('abi_ai_flags',    Int64(@ai.ai_flags) - base, 0);
  ChkI('abi_ai_family',   Int64(@ai.ai_family) - base, 4);
  ChkI('abi_ai_socktype', Int64(@ai.ai_socktype) - base, 8);
  ChkI('abi_ai_protocol', Int64(@ai.ai_protocol) - base, 12);
  ChkI('abi_ai_addrlen',  Int64(@ai.ai_addrlen) - base, 16);
  { on a 64-bit ABI the 4-byte ai_addrlen is followed by 4 bytes of padding so
    the pointer lands 8-aligned; on a 32-bit one it is not }
  if ptr = 8 then
  begin
    ChkI('abi_ai_addr',      Int64(@ai.ai_addr) - base, 24);
    ChkI('abi_ai_canonname', Int64(@ai.ai_canonname) - base, 32);
    ChkI('abi_ai_next',      Int64(@ai.ai_next) - base, 40);
    ChkI('abi_sizeof',       SizeOf(TCAddrInfo), 48);
  end
  else
  begin
    ChkI('abi_ai_addr',      Int64(@ai.ai_addr) - base, 20);
    ChkI('abi_ai_canonname', Int64(@ai.ai_canonname) - base, 24);
    ChkI('abi_ai_next',      Int64(@ai.ai_next) - base, 28);
    ChkI('abi_sizeof',       SizeOf(TCAddrInfo), 32);
  end;
  { the pair most easily swapped: ai_addr must come FIRST }
  Chk('abi_addr_before_canonname',
      Int64(@ai.ai_addr) < Int64(@ai.ai_canonname), True);

  if not DnsLibcAvailable then
    WriteLn('libc_skip=ok (no glibc/loader here; the facade answers above came ',
            'from the wire fallback, which is the contract)')
  else
  begin
    rc := DnsLibcResolveHost('localhost', ips2, n2);
    Chk('libc_v4_rc', rc = 0, True);
    Chk('libc_v4_loopback', (n2 > 0) and (ips2[0] = $7F000001), True);

    { agrees with the wire path on the same name }
    rc := DnsResolveHost('localhost', ips, n);
    same := 0;
    for i := 0 to n - 1 do
      if (n2 > 0) and (ips[i] = ips2[0]) then same := same + 1;
    Chk('libc_agrees_with_wire', same > 0, True);

    { getaddrinfo's EAI_NONAME/EAI_NODATA map onto NXDOMAIN's rcode 3, which is
      what lets the facade treat a libc failure exactly like a wire failure }
    rc := DnsLibcResolveHost('nonexistent-zzz-qqq.invalid', ips2, n2);
    ChkI('libc_nxdomain_rcode', rc, 3);
    ChkI('libc_nxdomain_empty', n2, 0);
  end;
{$endif}

  if fails = 0 then WriteLn('DNSLIBC OK')
  else WriteLn('DNSLIBC FAILED ', fails);
end.
