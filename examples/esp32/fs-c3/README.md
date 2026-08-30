# PXX → ESP-IDF PAL file-I/O baseline (ESP32-C3)

The on-target baseline for [[feature-pal-esp-posix-fd-semantics]]: it mounts FAT
on flash, drives the **real ESP PAL** file surface, and pins today's behaviour
including the two gaps that ticket exists to close.

```
PROBE: fat_mount rc=0
PAL: open-create ok
PAL: write n=7 (want 7)
PAL: seek rc=0
PAL: read n=7 (want 7)
PAL: content-mismatches=0
PAL: close rc=0
PAL: open-EXCL=-38 (today: -38 unsupported)
PAL: open-missing=-1 (today: -1, errno collapsed)
```

So **ESP-IDF VFS file I/O works under QEMU**, and so does the PAL's IDF path on
top of it. That had to be measured, not assumed: on the same emulator the GPIO
input path is entirely unmodelled and the first ADC call hangs, so "the ESP
peripherals are emulated" is false in general. File I/O happens to be one of the
parts that is real.

## Why this test lives on target, and why the host version of it is worthless

`feature-pal-esp-posix-fd-semantics` proposed pinning these semantics with
host-side `--platform=esp` tests, as the one thing doable without hardware.
Measured, that plan does not work:

```
$ pxx --platform=esp -Fulib/rtl/platform/esp excl.pas && ./excl
plain =-38
create=-38
excl  =-38
```

On the host the whole IDF backend is compiled out — `PXX_PAL_ESP_IDF_TARGET` is
set by `{$ifdef CPU_XTENSA}` / `{$ifdef CPU_RISCV32}` inside
`lib/rtl/platform/esp/platform_backend.pas`, so an x86-64 build has no file
backend at all and every call returns `PAL_ERR_UNSUPPORTED`. A host assertion
that `PAL_OPEN_EXCL` is refused therefore passes **whether or not the refusal
exists**, and would keep passing after someone implemented EXCL. It cannot
distinguish the thing it claims to pin.

What makes the on-target version meaningful is the row above it: `open-create`
**succeeds** in the same run. The successful open is the control — it proves the
backend is present and working, so the `-38` on the next line is a real refusal
rather than an absent implementation. Same assertion, opposite worth, and the
difference is entirely the control in the same run.

## The two pinned gaps

| row | today | what the ticket wants |
| --- | --- | --- |
| `open-EXCL=-38` | refused outright | exact O_EXCL create semantics |
| `open-missing=-1` | errno collapsed to -1 | errno-style negative (`-2` ENOENT), as POSIX PAL does |

`build.sh qemu-assert` fails when either moves. That is intended: if they move
because the ticket landed, the new values are the deliverable and `want=` should
be updated deliberately. If the create/write/read rows break instead, the PAL
file path regressed. The failure text says which is which.

## Running it

```bash
. ~/esp/esp-idf/export.sh
./build.sh              # build only
./build.sh qemu-assert  # build, boot, assert the baseline
```

Needs the custom partition table here (`partitions.csv` adds a `storage` FAT
partition); the stock single-app table has nowhere to mount. `sdkconfig.defaults`
selects it.

## Not covered

S3/xtensa. The ticket's acceptance names C3 **and** S3; this is C3 only. Nothing
here says whether the xtensa build behaves the same, and it should not be assumed
— that is a separate boot, on a separate QEMU binary.
