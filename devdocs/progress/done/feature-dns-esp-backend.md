---
track: B
prio: 20
type: feature
status: done
---

# DNS on ESP — bind lwIP's getaddrinfo, do NOT build a separate backend

**RE-SCOPED 2026-08-02 (user).** The original framing — a `dns_esp` resolver
backend alongside `dns_wire`/`dns_resolved`/`dns_libc` — is the wrong shape.
See "Design, settled" below.

- **Type:** feature (Track B networking / resolver backends), ESP-only
- **Split out of** [[feature-dns-backends-selection]] on 2026-08-02 (item 3),
  when that ticket's acceptance was met by `dns_resolved` landing.

## What it is

ESP-IDF/lwIP exposes its own resolver (`dns_gethostbyname` / lwIP's
`netconn_gethostbyname`) once the netif is up. On ESP, that resolver already
holds the DHCP-supplied nameservers and the lwIP DNS cache, so going through it
is both cheaper and more correct than re-deriving configuration.

## Correction 2026-08-02 — this is an ENABLER, not an optimisation

Filed claiming "`dns_wire` already works on ESP in principle — it is pure Pascal
over PAL — so this is an optimisation and an integration nicety, not an enabler.
Nothing is blocked on it." **That looks wrong**, and the open question below is
how it surfaced — it was checked rather than left hanging:

- `lib/rtl/dns_config.pas` has **zero** ESP handling (measured: no
  `PXX_PAL_ESP_IDF_TARGET` / `ESP_IDF` reference in it or in
  `dns_wire_blocking.pas`).
- `dns_wire` gets its nameservers from `/etc/resolv.conf` through the PAL.
  ESP-IDF does provide a VFS, so `PalOpen` itself would work — but nothing in
  this tree ever creates such a file on ESP, and an ESP device's DHCP-supplied
  nameservers live inside lwIP, not on a filesystem.

So on ESP `dns_wire` should reach `DNS_ERR_NOCONFIG` for every name, meaning DNS
does not work there at all and this ticket is the enabler. Re-ranked 20 → 35.

**Not run-verified.** This is read off the code and the ESP backend, not measured
on hardware — there is no ESP runner here. Confirm it on a device before trusting
it, because the point of this note is that the original claim was equally
plausible and equally unchecked.

The one thing that IS ESP-specific and already handled: `PalConnectUnix` reports
`PAL_NET_ENOTSUP` on the ESP backend, because lwIP has no filesystem sockets, so
`dns_resolved` can never be selected there. That is a clean refusal rather than
an obscure connect failure — see `lib/rtl/platform/esp/platform_backend.pas`.

## Shape

A `dns_esp` unit behind `-dPXX_DNS_ESP`, following exactly the pattern
`dns_resolved` established in `dns.pas`: the wire path stays compiled and is the
fallback, only `DnsResolveHost` / `DnsResolveHost6` dispatch, and selecting two
backends at once is a compile-time error (the guard already exists — extend it
to the new define).

Sequencing note, now answered: `dns_config` has no ESP story, so **this ticket
is really two** and should be split when picked up:

1. **Where do nameservers come from on ESP?** Either a `dns_config` source that
   reads lwIP's DHCP-supplied servers, or an app-supplied resolv.conf-shaped
   text. This half also fixes `dns_wire` on ESP and is worth doing even if the
   lwIP resolver backend never lands.
2. **The `dns_esp` backend proper** — hand the name to lwIP's own resolver so it
   uses its cache and its DHCP servers.

Doing (2) without (1) leaves `dns_wire` broken on ESP as the *fallback* path,
which is what every build without `-dPXX_DNS_ESP` gets.

## CORRECTION 2026-08-02 — it IS runnable here; my earlier note was wrong

An earlier revision of this ticket said "Not startable on the current fleet",
reasoning that `riscv32` under `qemu-riscv32` is Linux userspace with no lwIP,
so the backend could not be exercised. **That was wrong**, and wrong in the same
way as the `isatty` deferral in
[[feature-crtl-libc-gap-batch-2026-08]]: a real-sounding conclusion drawn from a
premise I never checked. I looked for USER-mode qemu and concluded no ESP runner
existed, without looking for system-mode.

What is actually here:

- **Espressif QEMU 9.2.2** — `qemu-system-xtensa` and `qemu-system-riscv32`
  under `~/.espressif/tools/`, machines `esp32`, `esp32s3`, `esp32c3`. Not on
  the default PATH; they come from ESP-IDF's export, which is why a bare
  `command -v` missed them.
- **ESP-IDF itself** at `~/esp/esp-idf`, with `tools/install_esp32_target.sh`
  in this repo installing exactly those two QEMU packages.
- **A working, exercised path.** [[feature-esp32-idf-xtensa]] records booting
  under `qemu-system-xtensa -M esp32s3` with the full IDF banner and serial
  output; [[bug-esp32s3-bare-boot-no-uart-output]] was found and fixed that way.

So this ticket can be started and verified, and the "Gate" below is achievable
rather than aspirational.

## Blocker RESOLVED same day — the ESP path works again

The blocker below turned out to be two missing flags in the examples' build
scripts, not a compiler defect:
`--platform=esp` (IDF heap) **and** `--no-signals` (no `rt_sigaction` in the
prologue), which are each silent on their own. Fixed in
[[bug-esp-examples-missing-platform-and-nosignals-flags]].

`net-c3` now boots once and prints `PXX-net-smoke status=0`, so **the ESP lwIP
socket path is proven working under QEMU on this box**, and this ticket's Gate
is reachable. What remains is the work itself, plus the user's standing
priority call that ESP is parked behind Pascal.

## The blocker as originally found (2026-08-02)

Establishing a baseline before starting this ticket turned up a hard blocker:
**every pxx ESP-IDF app currently panics the instant control reaches Pascal**,
on an unhandled Linux syscall (`ecall`) in the compiler-generated `app_main`
prologue. Both committed examples boot-loop; `net-c3`'s own smoke reports FAIL.
Filed as [[bug-esp-idf-linux-syscalls-emitted-panic-at-app-main]] (Track A).

That is the thing standing in front of this ticket — not the absence of a
runner, which is what an earlier revision wrongly claimed. It also means the
Gate below cannot pass today no matter how good the backend is, since the smoke
would die before reaching any DNS code.

## The other reason it sits low

**ESP is parked by the user** — "ESP parked (user 2026-07-12): Pascal has prio",
recorded in [[feature-pal-esp-posix-fd-semantics]]. That is a priority decision,
not a capability limit, and it is a perfectly good reason not to pick this up
unprompted. It is also a completely different statement from "cannot be run
here", and the difference matters to whoever reads this next.

## Gate

Runs on real ESP hardware (or QEMU-ESP where that exists) against a name the
lwIP resolver can answer; the host-side build must be unaffected, which the
existing `lib-test` DNS entries already assert by building the default and the
resolved variants. Cannot be gated on the normal x86-64 lib gate — state that
plainly in the ticket rather than pretending the usual gate covers it.

## Design, settled 2026-08-02 — measured, not assumed

**The user's point, and it is right:** an ESP program needs the IDF/lwIP stack
for networking anyway, and that stack already ships a DNS interface. So unless
the programmer explicitly opts into pxx's own resolver, DNS on ESP is already
solved — through the same POSIX-shaped API glibc offers, which puts it at the
`dns_libc` layer, **above the PAL**, not in a new backend.

### Verified in the installed IDF

`liblwip.a` contains all of it (checked with `nm` on the net-c3 build):

| symbol | in liblwip.a |
| --- | --- |
| `lwip_getaddrinfo` | yes |
| `lwip_freeaddrinfo` | yes |
| `lwip_gethostbyname` | yes |
| `dns_getserver` | yes |
| `dns_gethostbyname` | yes |

They do not appear in the *linked image* only because nothing references them
and the linker drops them — not because they are unavailable.

Note the real symbol is **`lwip_getaddrinfo`**; the plain `getaddrinfo` is a
`#define` in `lwip/netdb.h`, so a Pascal `external` must name the `lwip_` form.

### So the change is a BINDING difference, not a new backend

`dns_libc` already is "resolve through the platform's getaddrinfo". Only how the
symbol is acquired differs:

- **glibc**: `dlopen("libc.so.6")` + `dlsym`, because the syscall-only core is
  deliberately libc-free (hence `-dPXX_DYNLIB_LIBC`).
- **lwIP/ESP**: a direct `external 'lwip_getaddrinfo'` — statically linked by
  `idf.py`, no loader involved and no `-dPXX_DYNLIB_LIBC`.

That is an `{$ifdef}` around how `FnGetAddrInfo` is obtained. The list walking,
family filtering, error mapping and `TCAddrInfo` decoding are all shared.

### The ABI matches — but partly by coincidence, so pin it

`dns_libc` reads `struct addrinfo` and `sockaddr_in` **by offset**. Both are
compatible with lwIP, and one of them only by luck:

- **`struct addrinfo`**: identical field ORDER to glibc, including `ai_addr`
  before `ai_canonname`. On 32-bit that is 0/4/8/12/16/20/24/28 — exactly what
  `test/lib_dns_libc.pas` already pins for i386 and arm32.
- **`sockaddr_in`**: lwIP is BSD-style with a leading `u8_t sin_len` that glibc
  does not have. But lwIP's `sa_family_t` is `u8_t`, so
  `sin_len(1) + sin_family(1) + sin_port(2)` lands `sin_addr` at offset **4** —
  the same place glibc's `family(2) + port(2)` puts it. `sin6_addr` likewise
  coincides at 8.

**That coincidence must be asserted, not relied on.** If lwIP ever widened
`sa_family_t`, or someone "simplified" the two paths on the assumption the
structs are the same, every resolved address would silently shift by a byte.
The ESP test should assert the offsets the way `lib_dns_libc` does on host.

### What this leaves for `dns_wire` on ESP

It becomes the **explicit opt-in** case: someone who wants pxx's own resolver
rather than lwIP's (to bypass lwIP's cache, or to query a chosen server). Only
then does "where do nameservers come from on ESP" matter — and `dns_getserver`
is in `liblwip.a` for exactly that. Its `ip_addr_t` return is a union whose tag
offset moves with `LWIP_IPV6_SCOPES`, so that one *does* want a small C shim
using `ip_addr_get_ip4_u32()` rather than hand-computed offsets.

So the earlier PAL-nameserver plan is not wrong, just **not first**: it belongs
with the opt-in wire path, not on the default route.

### Target scope

**CORRECTION 2026-08-02 (user): xtensa is the PRIMARY ESP target** — most of the
user's devices are S2/S3, both xtensa. riscv32 (C3) is what works *today*, so it
stays the first thing to build against, but xtensa is the destination, not a
follow-up. The single blocker is
[[feature-xtensa-stack-args-over-6-words]] (re-ranked 45 -> 65), confirmed to be
the *only* error the xtensa ESP PAL build hits.

The original scope note said: Searched the board
rather than relying on recollection — the blockers below are what is actually
recorded, and they are more specific than "calling convention and FreeRTOS
bindings" (my earlier paraphrase of a from-memory remark).

**1. The real blocker for the ESP PAL on xtensa:**
[[feature-xtensa-stack-args-over-6-words]] (Track A, prio 45). The xtensa
backend caps both definitions and call sites at **6 parameter words**
(`parser.inc:10557`/`:10573`, `ir_codegen_xtensa.inc:1528`). `PalBackendVforkAndExec`
takes 7 (`path, argv, envp` + four fds), so

```
--target=xtensa --xtensa-abi=windowed -Fulib/rtl/platform/esp \
  test/lib_platform_esp.pas          -> fails at pascal26:647
```

**riscv32 is unaffected — its cap is 8**, which is exactly why the C3 path
works and the S3 one does not. So this *is* the calling convention, but
specifically argument passing beyond the in-register set, not windowed-vs-Call0.
That ticket also notes no workaround was applied: the 7-word signature is the
honest one and the fix belongs in the compiler.

**2. A second, narrower one:** [[feature-a-promoint-variant-esp-targets]] —
`--target=xtensa` gives `compiler error: __pxx_d2i not found (uses softfloat?)`
for Variant interop. riscv32 fails there too, differently.

**Not corroborated: "FreeRTOS bindings".** No open ticket attributes an xtensa
block to them, and `examples/esp32/hello-s3` links ESP-IDF through the same
`external` mechanism the working C3 examples use. Recorded so nobody chases it.

**Xtensa is not unexercised:** `make test-emit-obj` builds xtensa objects in
both Call0 and windowed ABIs (`Makefile:6315`/`:6322`), and `test_asmcore_xtensa`
runs in the gate.

**Separate gate, often conflated:** ESP32 *hardware* flash/boot validation is
[[feature-esp-hardware-flash-validation]] (Track A, blocked on physical
hardware), and the user is holding it until the compiler is stable on x86-64.
That is about silicon, not about whether this work can proceed — everything here
is QEMU-verifiable today.

`examples/esp32/hello-s3` therefore stays unchanged for now — deferred pending a
real `qemu-system-xtensa -M esp32s3` boot, not written off.

## 2026-08-30 — BUILT and verified under QEMU (frankB, Track B+S)

Implemented as the settled design specifies: a **binding difference inside
`dns_libc`**, not a new backend. Built and booted against pin v393
(`1d69760deabe2865`); the compiler was never rebuilt.

### What landed

| file | change |
| --- | --- |
| `lib/rtl/dns_libc.pas` | `{$ifdef PXX_ESP_IDF}{$define PXX_DNS_LWIP}{$endif}`; direct `external 'lwip_getaddrinfo'` / `'lwip_freeaddrinfo'`; `LibcInit` binds them instead of dlopen/dlsym; `dynlibs` dropped from `uses` on that arm; **lwIP's own `EAI_*` table and its own `EaiToRcode`** |
| `lib/rtl/dns.pas` | the `PXX_DNS_LIBC` → `PXX_DYNLIB_LIBC` guard now exempts `PXX_ESP_IDF` |
| `examples/esp32/dns-c3/**` | new IDF project + QEMU smoke, modelled on `net-c3` |

`Lookup`, `DnsLibcResolveHost`, `DnsLibcResolveHost6` and the `TCAddrInfo`
decoding are **untouched** — which was the point of siting this at `dns_libc`.

### The ticket's ABI analysis was right on every count — verified independently

Read out of the installed IDF's own headers rather than trusted:
`struct addrinfo` has glibc's field order exactly, `ai_addr` before
`ai_canonname` included (`lwip/netdb.h:103`). `sockaddr_in` is BSD-style with a
leading `u8_t sin_len` glibc lacks, but lwIP's `sa_family_t` is *also* `u8_t`
(`sockets.h:68`), so `sin_len(1)+sin_family(1)+sin_port(2)` puts `sin_addr` at
**4** — where glibc's `family(2)+port(2)` puts it. `sin6_addr` coincides at
**8** the same way. The coincidence holds.

### One thing the design did NOT have, and it was the only real hazard

**lwIP's `EAI_*` codes are positive 200-204; glibc's are negative -2..-5**, and
the sets differ — lwIP has no `EAI_AGAIN` and no `EAI_NODATA`
(`lwip/netdb.h:68-72`). Reusing glibc's numbers would have compiled, linked, and
resolved every valid name correctly, while misreporting every *failure*:
`EAI_NONAME` (200) misses every arm of `EaiToRcode`, falls out as
`DNS_ERR_LIBC_UNAVAIL`, and makes the facade fall back to `dns_wire` — which on
ESP has no nameserver config and answers `DNS_ERR_NOCONFIG`. **A name that does
not exist would be reported as "resolver unavailable."** Plausible, wrong, and
nowhere near the cause. `EaiToRcode` therefore has its own lwIP arm.

### Measured, under `qemu-system-riscv32` (Espressif fork), esp32c3

```
PXX-dns diag v4-rc=0        PXX-dns diag v6-rc=0        PXX-dns diag nx-rc=2
PXX-dns diag v4-count=1     PXX-dns diag v6-count=1
                            PXX-dns diag v6-loopback=1
PXX-dns-smoke status=0  ->  esp32c3 lwIP resolver smoke: PASS
```

`nx-rc=2` is the unplanned confirmation of the riskiest change: lwIP returned
`EAI_FAIL` (202) and it became SERVFAIL. With glibc's table the same run prints
`-22`. The v6 row was written as *non-gated* (a `CONFIG_LWIP_IPV6=n` device
answers `EAI_FAMILY`, a configuration fact rather than a defect) and passed
anyway, so the `sin6_addr@8` arm is exercised, not merely allowed for.

### Sufficiency and negative controls — the green is not vacuous

- **Symbol spelled right:** the emitted riscv32 object carries
  `U lwip_getaddrinfo` / `U lwip_freeaddrinfo` and **no bare `getaddrinfo`** —
  a wrong name would compile identically and fail only at link.
- **Both sides of the link:** `liblwip.a` defines `T lwip_getaddrinfo` /
  `T lwip_freeaddrinfo`.
- **The backend is what answered:** the smoke calls `DnsLibcResolveHost`
  *directly*, because the facade falls back on unavailability and a facade-level
  green cannot tell "lwIP answered" from "lwIP was skipped".
- **The assertions are live:** poisoning the expected loopback constant
  (`$7F000001` → `$7F000002`) and rebuilding gave `status=48` — bit 16 (wrong
  value) + bit 32 (facade disagrees), exactly the two bits that should light —
  and `status=0` returned when restored.
- **Host arms unaffected:** glibc backend still resolves (`rc=0 n=2`), the
  loader guard still fires on a hosted build without `-dPXX_DYNLIB_LIBC`, and
  the default wire path is unchanged.

### Scope — what is NOT done, stated plainly

**This is the binding and the ABI. It is not "DNS works on ESP".** The smoke
resolves *numeric literals*, which `getaddrinfo` converts locally with no query
and no server — which is precisely why they work under QEMU with no network. Not
covered: a real DNS query, the DHCP-supplied nameservers, lwIP's cache. Closing
that needs a device on real Wi-Fi, and the ticket's Gate anticipated this by
saying "against a name the lwIP resolver can answer".

**xtensa is untouched** and remains blocked by
[[feature-xtensa-stack-args-over-6-words]] (the 6-parameter-word cap;
riscv32's is 8, which is why C3 works and S3 does not). Nothing here changes
that, and the user's ruling that xtensa is the primary ESP target still stands —
this is the riscv32 half of the destination, not the destination.

**Half 1 of the split stays open.** The ticket says it "is really two", and the
settled design put the nameserver question *second*, with the opt-in wire path.
That half is now filed separately as
[[feature-dns-esp-wire-nameservers-from-lwip]] so this one can close on what it
actually delivered.

### Gate

Per the ticket's own note, the normal x86-64 lib gate cannot cover this and
saying so plainly was required. What was actually run: `make lib-test` for the
host side (the shared `dns.pas` / `dns_libc.pas` edits), plus the QEMU boot above
for the ESP side. The compiler was not rebuilt; everything used
`$(PXX_STABLE)`.

## Log
- 2026-08-30 — resolved, commit fecc7f85c.
