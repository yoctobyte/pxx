# PXX → ESP-IDF lwIP resolver smoke (ESP32-C3)

Proves that `dns_libc` binds **lwIP's `getaddrinfo`** on ESP-IDF
(`feature-dns-esp-backend`). `main/main.pas` is compiled
(`--target=riscv32 --platform=esp --no-signals -dPXX_DNS_LIBC`) against the ESP
PAL backend to a relocatable object, wrapped in a static archive, and linked by
the normal `idf.py build` as the provider of `app_main` — the same shape as
`net-c3`, which exercises the PAL socket surface rather than the resolver.

## Why this is a binding, not a backend

The user's ruling: an ESP program links the IDF/lwIP stack for networking
anyway, and that stack already ships a resolver holding the DHCP-supplied
nameservers and lwIP's cache. So DNS on ESP is a **binding difference at the
`dns_libc` layer**, above the PAL — not a new backend below it. Only how the
symbol is acquired differs:

| | how `getaddrinfo` is obtained |
| --- | --- |
| glibc | `dlopen("libc.so.6")` + `dlsym`, because the syscall-only core is deliberately libc-free — hence `-dPXX_DYNLIB_LIBC` |
| lwIP / ESP | a direct `external 'lwip_getaddrinfo'`, statically linked by `idf.py`. No loader, and **`-dPXX_DYNLIB_LIBC` is not required** |

`dns.pas` exempts ESP from the guard that normally demands the loader. The
exemption is narrow: the compiler sets `PXX_ESP_IDF` only for `--platform=esp`
on an ESP ISA, so a hosted build cannot reach it.

The symbol is `lwip_getaddrinfo`, **not** `getaddrinfo` — the plain name is a
`#define` in `lwip/netdb.h`, so an external naming it would compile and then
fail at link.

## What the smoke tests, and what it does not

It resolves **numeric literals** (`127.0.0.1`, `::1`). `getaddrinfo` converts
those locally, with no query and no server, which is exactly why they work under
QEMU with no network. So the smoke covers the binding and the ABI:

- `lwip_getaddrinfo` / `lwip_freeaddrinfo` resolve at link time
- the `TCAddrInfo` walk (`ai_family` / `ai_addr` / `ai_next`) reads lwIP's layout
- `sin_addr` really is at offset 4 and `sin6_addr` at 8 — asserted **by value**,
  because a one-byte shift yields a *different address*, not a failure

It does **not** cover a real DNS query, the DHCP-supplied nameservers, or lwIP's
cache. Those need a network and a server, which QEMU's loop interface has not
got. **A green here is not "DNS works on ESP"** — it is "the lwIP resolver is
correctly bound and correctly decoded". A device on real Wi-Fi closes the other
half.

The backend is called **directly** (`DnsLibcResolveHost`), not through the `dns`
facade: the facade falls back to `dns_wire` when a backend reports itself
unavailable, so a facade-level green cannot distinguish "lwIP answered" from
"lwIP was skipped and something else answered". One facade call runs last as an
integration check, after the direct calls have established which backend is live.

## Build

```bash
. ~/esp/esp-idf/export.sh     # idf.py + toolchains on PATH
./build.sh                    # main.pas -> main.o -> libpxx_app.a, then idf.py build
```

The component links `lwip` + `esp_netif` via the prebuilt library's own
`REQUIRES` (a plain component `REQUIRES` leaves the prebuilt archive outside the
link group, so its `lwip_*` / `esp_netif_init` refs go unresolved).

## Run under Espressif QEMU (headless, asserts)

```bash
./build.sh qemu
```

Measured 2026-08-30 against pin v393 (`1d69760deabe2865`):

```
PXX-dns diag v4-rc=0
PXX-dns diag v4-count=1
PXX-dns diag v6-rc=0
PXX-dns diag v6-count=1
PXX-dns diag v6-loopback=1
PXX-dns diag nx-rc=2
PXX-dns-smoke status=0
esp32c3 lwIP resolver smoke: PASS
```

`status` folds one bit per gated failure stage; `0` is all-pass. The `diag` lines
are **not** gated — they are printed so two different situations cannot look
identical:

- **`v6-*`** — a build with `CONFIG_LWIP_IPV6=n` answers `EAI_FAMILY` here. That
  is a fact about the device's lwIP configuration, not a defect in the binding,
  so it is reported rather than failed. `sdkconfig.defaults` pins IPv6 on so the
  `sin6_addr@8` arm is actually exercised; `v6-loopback=1` means the 16 bytes
  came back as exactly `::1`.
- **`nx-rc`** — a name with no answer. Under QEMU there is no server, so the
  value depends on what lwIP does with no nameserver configured. It is printed
  because the `EAI_*` mapping is the one place this binding could be *silently*
  wrong, and this is where that becomes visible on a device that has a network.

### The `EAI_*` trap, and why `nx-rc=2` is the interesting line

**lwIP's `getaddrinfo` error codes are positive 200–204; glibc's are negative
−2…−5**, and the sets differ — lwIP has no `EAI_AGAIN` and no `EAI_NODATA`
(`lwip/src/include/lwip/netdb.h:68`). A binding that reused glibc's numbers
would compile, link, and resolve every valid name correctly, then misreport
every *failure*: `EAI_NONAME` (200) would miss every arm of `EaiToRcode`, fall
out as `DNS_ERR_LIBC_UNAVAIL`, and make the facade fall back to `dns_wire` —
which on ESP has no nameserver configuration and answers `DNS_ERR_NOCONFIG`. A
caller asking for a name that does not exist would be told the resolver is
unavailable.

`nx-rc=2` is that mapping working: lwIP returned `EAI_FAIL` (202) and it became
SERVFAIL. With glibc's table the same run would have printed `-22`.

## Negative control

The assertions were confirmed live rather than vacuous by poisoning the expected
loopback constant (`$7F000001` → `$7F000002`) and rebuilding: the smoke reported
`status=48` — bit 16 (wrong IPv4 value) plus bit 32 (facade disagrees), the two
bits that should light — then returned to `status=0` when restored.
