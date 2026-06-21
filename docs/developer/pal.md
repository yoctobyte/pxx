# Platform Abstraction Layer

The Platform Abstraction Layer (PAL) is the only RTL layer that may branch on
`PXX_PLATFORM_*`. Higher-level units should depend on `lib/rtl/platform.pas`
instead of checking platform names directly.

## Platform Model

`posix` means hosted Linux/POSIX-style services: file descriptors, syscalls,
sockets, threads, and dynamic libraries as capabilities allow.

`esp` means ESP-IDF/FreeRTOS hosted code. It does **not** mean the bare-metal
ESP boot path. Bare remains useful for compiler and low-level target tests, but
PAL backends should be shaped around IDF services such as VFS, lwIP, FreeRTOS
tasks, and `esp_timer`.

## Current Interface

`uses platform;`

- `PalPlatform: Integer`
  - `PAL_PLATFORM_POSIX`
  - `PAL_PLATFORM_ESP_IDF`
- Capability queries:
  - `PalHasFiles`
  - `PalHasSockets`
  - `PalHasThreads`
  - `PalHasDynlib`
- Byte-handle primitives:
  - `PalOpen(path, flags, mode)`
  - `PalRead(handle, buf, len)`
  - `PalWrite(handle, buf, len)`
  - `PalSeek(handle, offset, whence)`
  - `PalTell(handle)`
  - `PalFlush(handle)`
  - `PalClose(handle)`
  - `PalDelete(path)`
  - `PalRename(oldPath, newPath)`
  - `PalMkdir(path, mode)`
  - `PalRmdir(path)`
- Socket primitives:
  - `PalSocket(domain, kind, proto)`
  - `PalSetSocketReuseAddr(handle, enabled)`
  - `PalSetSocketNonBlocking(handle, enabled)`
  - `PalBindIpv4(handle, hostAddr, port)`
  - `PalConnectIpv4(handle, hostAddr, port)`
  - `PalListen(handle, backlog)`
  - `PalAccept(handle)`
  - `PalRecv(handle, buf, len)`
  - `PalSend(handle, buf, len)`
  - `PalShutdown(handle, how)`
  - `PalSocketClose(handle)`
- Scheduler/clock hooks:
  - `PalYield`
  - `PalMonotonicMillis`

`PAL_ERR_UNSUPPORTED` is the portable "not implemented on this backend yet"
result. It currently uses `-38` (`ENOSYS`).

## Current Backends

The posix backend implements byte-handle open/read/write/seek/flush/close,
basic filesystem mutation, and IPv4 TCP socket primitives using raw Linux
syscalls on the hosted CPU targets. `PalMonotonicMillis` is a placeholder and
currently returns `0`.

The ESP backend is IDF-shaped. On real ESP CPU targets, `PalYield` and
`PalMonotonicMillis` are wired to `vTaskDelay` and `esp_timer_get_time`.
File handles are backed by ESP-IDF/newlib stdio (`fopen`/`fread`/`fwrite`/
`fseek`/`fflush`/`fclose`) plus VFS mutation calls (`remove`/`rename`/`mkdir`/
`rmdir`). Socket handles are backed by ESP-IDF/lwIP BSD-socket calls
(`lwip_socket`/`lwip_bind`/`lwip_connect`/`lwip_listen`/`lwip_accept`/
`lwip_recv`/`lwip_send`/`lwip_shutdown`/`lwip_close`). File IO requires the app
or board support to register/mount an actual VFS filesystem; sockets require the
app to bring up the relevant ESP network interface. PAL only supplies the
porting seam. Native `--platform=esp` smoke tests avoid linking IDF symbols so
capability and unsupported-path behavior can be tested on the host without a
host-libc fallback.

The first socket slice is IPv4 TCP only. Addresses passed to `PalBindIpv4` and
`PalConnectIpv4` are host-order IPv4 integers such as `PAL_NET_IP_LOOPBACK`
(`127.0.0.1`) and `PAL_NET_IP_ANY`.

## Rules

- Do not add platform `{$ifdef}`s above `lib/rtl/platform.pas`.
- Gate higher-level libraries on capability defines or PAL unsupported returns,
  not on CPU names.
- Keep PAL primitives small enough to implement on both posix and ESP-IDF.
- Keep async out of PAL. PAL exposes socket operations, nonblocking mode, and
  readiness/error primitives; blocking `net.pas` and coroutine-backed
  `asyncnet.pas` are separate top-level libraries above it.
- When the Pascal unit search-path selector lands, split the backend into
  per-platform units and remove the interim single-unit branch.
