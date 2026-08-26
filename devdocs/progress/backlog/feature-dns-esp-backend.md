---
track: B
prio: 20
type: feature
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
