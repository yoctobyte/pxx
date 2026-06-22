# PXX → ESP-IDF lwIP socket smoke (ESP32-C3)

Proves the PXX **PAL socket surface** runs on real ESP-IDF lwIP. `main/main.pas`
is compiled (`--target=riscv32`) against the ESP PAL backend
(`lib/rtl/platform/esp`) to a relocatable object, wrapped in a static archive,
and linked by the normal `idf.py build` as the provider of `app_main`.

It runs a **UDP loopback** exchange over the 127.0.0.1 loop interface
(`LWIP_HAVE_LOOPIF`, on by default via `CONFIG_LWIP_NETIF_LOOPBACK`), so it needs
**no Wi-Fi / Ethernet** — only `esp_netif_init` to start the lwIP TCP/IP task:
bind a datagram socket to `127.0.0.1:3333`, send to it, `PalPoll` for readiness,
`PalRecvFromIpv4` the payload. The host equivalent is
`test/lib_platform_net_udp.pas` (POSIX, same path).

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

Boots `qemu-system-riscv32` (Espressif fork), captures serial, and asserts:

```
PXX-net-smoke status=0
esp32c3 lwIP loopback socket smoke: PASS
```

`status=0` means the core path passed: socket / bind / sendto / poll /
recvfrom + loopback delivery. The address **read-back** diagnostics
(`bound-port` / `peer-port`) currently print `0` — lwIP returns an unfilled
sockaddr from `getsockname` / `recvfrom` here; tracked by
`docs/progress/backlog/feature-pal-esp-lwip-sockaddr-readback.md`. They are not
gated so the smoke reflects the proven plumbing.

## Notes

- `esp32s3` (Xtensa) is **not** buildable yet: the PAL unit's 7-word
  `PalBackendVforkAndExec` trips the Xtensa 6-parameter-word cap
  (`feature-xtensa-stack-args-over-6-words`). esp32c3 (riscv32, 8-word cap) is
  fine.
- Uses the portable PAL directly, not `net.pas`: net.pas's by-value
  `TNetAddress` helpers hit a riscv32 record-result codegen gap
  (`feature-riscv32-record-function-results`).
- Real-hardware flashing should work with `idf.py flash monitor` but is
  untested (no C3 board on hand).
