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

  NETWORK — measured with strace on THESE binaries, not on a proxy. An earlier
  version of this comment said "NO NETWORK: every lookup is `localhost`", and
  a first attempt to correct it straced glibc's getaddrinfo, which was a clean
  and irrelevant answer: the default build does not use glibc at all, it uses
  our own wire resolver. On the real binaries the default build made 6 contacts
  to port 53 and the libc build 12. After the fix below: 0 and 6, the remaining
  six being the deliberate `.invalid` row.

  The cause is one row, and it is now fixed. `/etc/hosts` on Debian/Ubuntu maps
  `127.0.0.1 localhost` but spells the v6 loopback `ip6-localhost`, so there is
  no `::1 localhost` line. `DnsResolveHost('localhost')` therefore hits files
  and stays local, while `DnsResolveHost6('localhost')` MISSED files, fell
  through to the wire, and queried `localhost.home`, `localhost.<search>` and
  `localhost.` against the configured nameserver — and the row then asserted
  rc = 0, so it passed only because the network answered.

  That is the same defect as the header lie one level in: a row that works on
  this box for a reason unrelated to what it claims to check. The v6 row now
  resolves the LITERAL `::1`, which short-circuits without network (measured:
  zero contacts to port 53). The v4 row keeps `localhost`, which is a files hit
  on any box with the conventional /etc/hosts line.

  Underneath this sits a real resolver defect, filed separately: our resolver
  has no `localhost` special-case at all, so it sends the name to the wire and
  uses whatever comes back. RFC 6761 section 6.3 says name resolution APIs
  SHOULD recognise localhost names as special and SHOULD always return the
  loopback address. glibc complies (zero port-53 contacts, answers
  ::ffff:127.0.0.1); we do not. See bug-b-resolver-sends-localhost-to-the-wire.
  Note that `.invalid` carries a DIFFERENT prescription (section 6.4: immediate
  negative responses), so glibc's willingness to query `.invalid` says nothing
  about `localhost` — an inference worth not repeating.

  The libc half's NXDOMAIN row still resolves `nonexistent-zzz-qqq.invalid`
  through getaddrinfo and that DOES go to the network (6 contacts to port 53 in
  this binary; 9 in a standalone getaddrinfo probe),
  by design: it is testing that EAI_NONAME maps onto rcode 3. On a box with no
  resolver, or a slow one, that row can see EAI_AGAIN instead and fail. It is
  guarded behind PXX_DNS_LIBC, so the default build never reaches it.

  SKIPS its libc half where glibc or the loader is absent — that is a supported
  configuration, covered by the facade falling back to wire. }
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
  { The literal, NOT the name: `localhost` has no AAAA in /etc/hosts on
    Debian/Ubuntu, so asserting rc = 0 for it passed only because the wire
    answered. A literal short-circuits without network. }
  rc := DnsResolveHost6('::1', ip6, n);
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
