---
prio: 20
---

# ESP PAL: exact POSIX fd semantics over ESP-IDF VFS

- **Type:** feature (Track B PAL / ESP-IDF)
- **Status:** backlog — unblocked (bug-esp-idf-heap-linux-mmap-ecall resolved 2026)
- **Owner:** —
- **Opened:** 2026-06-21 (PAL file IO expansion)
- **Relation:** follows `feature-platform-abstraction-layer`

## Problem

The first ESP-IDF PAL file backend uses newlib stdio (`fopen`/`fread`/`fwrite`/
`fseek`/`fflush`/`fclose`) over ESP-IDF VFS. That gives real file contents on
mounted IDF filesystems without touching compiler code, but it is not exact
POSIX fd semantics:

- `PAL_OPEN_EXCL` returns `PAL_ERR_UNSUPPORTED` on ESP for now.
- Standard PAL handles `0`/`1`/`2` are not mapped to ESP-IDF stdin/stdout/stderr.
- Errors collapse to `-1` for stdio failures instead of preserving errno-style
  negative codes.
- Seek offsets are limited by the C `fseek`/`ftell` surface used here.

Direct IDF/POSIX `open`/`read`/`write`/`close` would be a better long-term
match, but `read`/`write` are Pascal keyword tokens today, so a clean direct
external binding needs either imported C declarations with safe Pascal names or
a compiler-supported external symbol alias that preserves the local Pascal
identifier.

## Acceptance

- ESP PAL can open files with exact create/exclusive/truncate/append semantics.
- ESP PAL preserves errno-style negative results consistently with POSIX PAL.
- `PAL_STDIN`/`PAL_STDOUT`/`PAL_STDERR` work on ESP-IDF where the app has
  configured console VFS.
- The implementation is validated by an ESP-IDF link/run smoke on C3 and S3, not
  only host `--platform=esp` unsupported-path tests.

## Log

- 2026-06-21 — Opened while extending PAL file IO. Current stdio-backed ESP path
  is source/object-valid and imports the expected IDF/newlib symbols, but exact
  fd semantics are intentionally left as this follow-up rather than hidden in
  PAL workarounds.

- 2026-07-19 (backlog sweep note) Stale blocker ref: bug-esp-idf-heap-linux-mmap-ecall is resolved (in done/). Ticket itself still fully open (ESP backend stdio-based, PAL_OPEN_EXCL unsupported).

## Moved to blocked/ (2026-07-20, Track B sweep)

Acceptance is a C3/S3 link-and-run smoke; there is no device and no qemu/IDF
runner in this lane. External constraint, so `blocked/` rather than backlog.

One thing IS doable without hardware and is worth doing first when this resumes:
host-side `--platform=esp` tests that pin the CURRENT behaviour — `PAL_OPEN_EXCL`
returning `PAL_ERR_UNSUPPORTED`, and the errno collapse — so the rewrite has a
baseline to diff against instead of changing semantics blind.

## Moved to blocked/ 2026-07-31 (Track B sweep) — same wall as the rest of the ESP family

This ticket's own acceptance ends with "validated by an ESP-IDF link/run smoke
on C3 and S3, **not only** host `--platform=esp` unsupported-path tests". That
is the part nothing here can do: re-checked rather than assumed, this box has no
`qemu-system-riscv32`, no `qemu-system-xtensa`, `IDF_PATH` unset, and no board.
An ESP-IDF checkout at `~/esp/esp-idf` is enough to LINK and nothing more.

Writing exact POSIX fd semantics that nobody can execute would produce precisely
what the honest-refusal discipline in this backend exists to avoid: code that
looks right. The current newlib-stdio backend already refuses what it cannot do
(`PAL_OPEN_EXCL` -> `PAL_ERR_UNSUPPORTED`), which is the correct resting state.

**Tagged for later testing** with [[feature-esp-peripheral-callback-api]]: when a
C3/S3 board or a working qemu-IDF harness appears, both wake up together. Nothing
from this ticket enters the regression suite until something can run it.

## Inventory 2026-08-02 — what "not a Unix" actually costs, measured

The user's framing: ESP32 is *"not a unix at all, just a thin layer of
FreeRTOS"*, so it will carry its own incompatibility set. Counted from
`lib/rtl/platform/esp/platform_backend.pas`, separating the two cases that a
naive grep conflates:

**Refused even under ESP-IDF — 33 PAL entry points.** This is the real gap list:

| area | refused |
| --- | --- |
| **process model** | `Vfork` `VforkAndExec` `Execve` `Wait4` `Kill` `Pipe2` |
| **filesystem metadata** | `Stat` `StatAt` `Fstat` `Lstat` `Access` `GetDents64` `Readlink` `Utimes` `Fchmod` `Fchown` `Ftruncate` `Fsync` `Fcntl` `Dup2` |
| **namespace** | `Chdir` `Getcwd` `Symlink` `Link` |
| **memory** | `MmapAnon` `Munmap` |
| **IPv6** | `BindIpv6` `ConnectIpv6` `AcceptIpv6` `SendToIpv6` `RecvFromIpv6` |
| **time** | `Nanosleep` `Realtime` |

**Works under IDF, refused only on bare — 25.** The IPv4 socket surface
(`Socket` `BindIpv4` `ConnectIpv4` `Listen` `Accept` `Send` `Recv`
`SendToIpv4` `SetSockOpt` `GetSockOpt` `Ioctl` `Shutdown` `SocketClose`
`SetSocketNonBlocking` `SetSocketReuseAddr`) plus basic file I/O over the IDF
VFS (`Open` `Read` `Write` `Seek` `Close` `Flush` `Delete` `Rename` `Mkdir`
`Rmdir`).

### The shape of it

**Sockets work; basic file I/O works; almost everything else Unix-shaped is
absent.** FreeRTOS has tasks, not processes — so there is no fork/exec/wait/kill
and no pipes. There is no working directory, no links, no ownership, no
directory enumeration and no `stat`. There is no virtual memory (the IDF heap
replaces `mmap`). That is not a set of missing features to fill in one by one:
it is a different OS model, and code that assumes POSIX will meet it as
`PAL_ERR_UNSUPPORTED` rather than as a wrong answer — which is the right
failure mode and worth preserving.

### Consequence for lib/crtl

The crtl additions of 2026-08-02 (`pipe`, `kill`, `dup`/`dup2`, `chdir`,
`symlink`, `link`, `getuid`/`getgid`/`getegid`/`getppid`) are POSIX-shaped and
several land on the always-refused list above. They are honest on ESP — the PAL
returns unsupported rather than faking — but a C program ported to ESP will hit
them. Worth knowing before anyone reads the crtl gap-batch tickets as "crtl is
now complete for every target": it is complete for the **hosted** targets.

## 2026-08-09 (Track B): this is also the ROOT FIX for the close() dispatch bug

[[bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file]] exists only because of
the design this ticket proposes to replace. On IDF today a file handle IS a
`FILE*` from `fopen` cast to Integer, while a socket handle is a small lwip VFS
fd — two disjoint namespaces sharing one `Integer`, which is why crtl's single
`close(int fd)` cannot dispatch and why that ticket's "option 2, unify in the
PAL" is hard.

Move the ESP file backend onto direct POSIX `open`/`read`/`write`/`close` as
proposed here and the dispatch problem **disappears** rather than being solved:
both handles become real VFS fds in one namespace, and one `close()` is correct
for both. So the close ticket's option 2 is really "do this ticket", and its
option 1 (an fd registry in crtl) is a workaround for a design that is already
scheduled to change.

Worth doing in this order rather than the other way round.

Noted while defanging the close bug's worst symptom (it now refuses a
non-pointer handle instead of `fclose`-ing an lwip fd). That mitigation is
independent and stays useful until this lands.

## Cannot be completed on this box

The acceptance above requires "an ESP-IDF link/run smoke on C3 and S3, not only
host `--platform=esp` unsupported-path tests" — correctly, since the whole point
is real VFS behaviour. There is no ESP32 here, so the implementation can be
written and the riscv32/xtensa objects built, but the ticket cannot be CLOSED
without a device.

