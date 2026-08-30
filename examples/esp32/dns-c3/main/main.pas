{ SPDX-License-Identifier: 0BSD }
program Esp32DnsSmoke;
{ PXX -> ESP-IDF lwIP resolver smoke (ESP32-C3 / riscv32), feature-dns-esp-backend.

  Proves that `dns_libc` -dPXX_DNS_LIBC binds lwIP's getaddrinfo on ESP: the
  symbol links, the addrinfo list walks, and the sockaddr_in offset this backend
  reads by hand is the right one on lwIP's BSD-style struct.

  WHAT THIS DOES AND DOES NOT TEST -- read before trusting a green.

  It resolves NUMERIC literals ('127.0.0.1', '::1'). getaddrinfo converts those
  locally, with no query and no server, which is exactly why they work under
  QEMU with no network. So this smoke covers the BINDING and the ABI:

    - lwip_getaddrinfo / lwip_freeaddrinfo resolve at link time
    - the TCAddrInfo walk (ai_family / ai_addr / ai_next) reads lwIP's layout
    - sin_addr really is at offset 4 and sin6_addr at 8 -- asserted by VALUE,
      since a one-byte shift would yield a different address, not a failure

  It does NOT cover: a real DNS query, the DHCP-supplied nameservers, or lwIP's
  cache. Those need a network and a server, which QEMU's loop interface has not
  got. A device on real Wi-Fi is what closes that half, and until then this
  smoke must not be read as "DNS works on ESP" -- only as "the lwIP resolver is
  correctly bound and correctly decoded".

  The backend is called DIRECTLY (DnsLibcResolveHost), not through the `dns`
  facade, on purpose: the facade falls back to dns_wire when a backend reports
  itself unavailable, so a facade-level green cannot distinguish "lwIP answered"
  from "lwIP was skipped and something else answered". One facade call is made
  at the end as an integration check, after the direct calls have already
  established which backend is live.

  Status bits, one per failure stage, folded into one word (0 = all pass). }

uses platform, dns, dns_libc, dns_wire_core;

procedure esp_rom_printf(fmt: string; v: Integer); external;
function esp_netif_init: Integer; external;
procedure vTaskDelay(ticks: Integer); external;

const
  IP_LOOPBACK_HOST = $7F000001;   { 127.0.0.1 in host order }

var
  ips: TDnsIpv4Array;
  ips6: TDnsIpv6Array;
  n, rc, status, j: Integer;
  v6ok: Boolean;

begin
  status := 0;

  { lwIP's TCP/IP task must be running before the resolver is usable. }
  rc := esp_netif_init;
  if rc <> 0 then status := status or 1;
  vTaskDelay(50);

  { The backend must report itself live. On ESP this is a pure binding check --
    there is no loader to fail, so a False here means the externals did not
    bind, which should have been a link error rather than a runtime one. }
  if not DnsLibcAvailable then status := status or 2;

  { IPv4: the value assertion IS the offset assertion. sin_addr sits at 4 on
    lwIP only because sin_len and sin_family are both u8_t; if that ever stops
    being true this comes back shifted, not empty. }
  n := 0;
  rc := DnsLibcResolveHost('127.0.0.1', ips, n);
  esp_rom_printf('PXX-dns diag v4-rc=%d'#10, rc);
  esp_rom_printf('PXX-dns diag v4-count=%d'#10, n);
  if rc <> 0 then status := status or 4;
  if n <> 1 then status := status or 8;
  if (n >= 1) and (ips[0] <> IP_LOOPBACK_HOST) then status := status or 16;

  { IPv6: sin6_addr at 8. NOT gated -- a build with CONFIG_LWIP_IPV6=n answers
    EAI_FAMILY here, which is a fact about the device's lwIP configuration and
    not a defect in this binding. Printed so the two cases are distinguishable
    instead of silently identical. }
  n := 0;
  rc := DnsLibcResolveHost6('::1', ips6, n);
  esp_rom_printf('PXX-dns diag v6-rc=%d'#10, rc);
  esp_rom_printf('PXX-dns diag v6-count=%d'#10, n);
  if (rc = 0) and (n >= 1) then
  begin
    v6ok := True;
    for j := 0 to 14 do
      if ips6[0][j] <> 0 then v6ok := False;
    if ips6[0][15] <> 1 then v6ok := False;
    if v6ok then esp_rom_printf('PXX-dns diag v6-loopback=%d'#10, 1)
    else esp_rom_printf('PXX-dns diag v6-loopback=%d'#10, 0);
  end;

  { A name with no answer. Under QEMU there is no server, so this is a
    DIAGNOSTIC, not a gate: it may be NXDOMAIN (3), a backend error, or a
    timeout depending on what lwIP does with no nameserver configured. It is
    printed because the EAI mapping for lwIP's positive 200-204 codes is the one
    place this binding could be silently wrong, and seeing the number here is
    how that gets noticed on a device that does have a network. }
  n := 0;
  rc := DnsLibcResolveHost('no-such-host.invalid', ips, n);
  esp_rom_printf('PXX-dns diag nx-rc=%d'#10, rc);

  { Integration: the same lookup through the facade must agree with the direct
    call. Runs last so the direct calls above have already proven which backend
    is answering. }
  n := 0;
  rc := DnsResolveHost('127.0.0.1', ips, n);
  if (rc <> 0) or (n <> 1) or (ips[0] <> IP_LOOPBACK_HOST) then
    status := status or 32;

  esp_rom_printf('PXX-dns-smoke status=%d'#10, status);

  { app_main has no returning epilogue yet; park so the WDT stays fed. }
  while True do
    vTaskDelay(1000);
end.
