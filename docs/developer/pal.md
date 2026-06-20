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
  - `PalRead(handle, buf, len)`
  - `PalWrite(handle, buf, len)`
  - `PalClose(handle)`
- Scheduler/clock hooks:
  - `PalYield`
  - `PalMonotonicMillis`

`PAL_ERR_UNSUPPORTED` is the portable "not implemented on this backend yet"
result. It currently uses `-38` (`ENOSYS`).

## Current Backends

The posix backend implements byte-handle read/write/close using raw Linux
syscalls on the hosted CPU targets. `PalMonotonicMillis` is a placeholder and
currently returns `0`.

The ESP backend is IDF-shaped. On real ESP CPU targets, `PalYield` and
`PalMonotonicMillis` are wired to `vTaskDelay` and `esp_timer_get_time`.
Byte-handle IO returns `PAL_ERR_UNSUPPORTED` until VFS/lwIP bindings are added.
Native `--platform=esp` smoke tests avoid linking IDF symbols so capability and
unsupported-path behavior can be tested on the host.

## Rules

- Do not add platform `{$ifdef}`s above `lib/rtl/platform.pas`.
- Gate higher-level libraries on capability defines or PAL unsupported returns,
  not on CPU names.
- Keep PAL primitives small enough to implement on both posix and ESP-IDF.
- When the Pascal unit search-path selector lands, split the backend into
  per-platform units and remove the interim single-unit branch.
