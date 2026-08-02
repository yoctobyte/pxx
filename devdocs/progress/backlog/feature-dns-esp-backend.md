---
track: B
prio: 35
type: feature
---

# `dns_esp` — the lwIP resolver on ESP targets

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
