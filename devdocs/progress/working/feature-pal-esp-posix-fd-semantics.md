---
prio: 20
track: B
type: feature
status: working
blocked-by: []
summary: "Exact POSIX fd semantics for the ESP PAL over IDF VFS, replacing the newlib-stdio backend. UNBLOCKED 2026-09-02: bug-a-emit-obj-ignores-external-name-and-emits-the-pascal-identifier is in done/. ACCEPTANCE IS RUNNABLE ON THIS BOX AND THAT SENTENCE WAS FALSE -- measured 2026-09-23, this ticket said `which this box cannot do` since 2026-09-02: `examples/esp32/fs-c3/build.sh qemu-assert` does a real IDF link and boots C3 under Espressif qemu, rc=0, `OK fs-c3 -- ESP PAL file I/O works on target; EXCL and errno gaps pinned`. It is wired into `make test-esp-idf`, and it already pins THIS TICKET'S EXACT TWO ROWS -- `PAL: open-EXCL=-38 (today: -38 unsupported)` and `PAL: open-missing=-1 (today: -1, errno collapsed)` -- with a failure message that says moving them IS this ticket landing. The harness was built for this work and nobody told the ticket. The S3 arm is still unmeasured: fs-c3 is C3-only and there is no fs-s3. The baseline the ticket asked for IS NOW LANDED, but NOT in the shape the ticket suggested: a host-side --platform=esp test would pin the STUB, because the whole stdio/IDF arm is under {$ifdef PXX_PAL_ESP_IDF_TARGET}, set only for CPU_XTENSA/CPU_RISCV32 -- so on the host every PAL file call returns PAL_ERR_UNSUPPORTED and such a row would pass identically before and after the rewrite. The landed baseline builds the fixture for both ESP targets and asserts the newlib stdio symbol imports, with the host build (0 of 7) as its negative control."
---

# ESP PAL: exact POSIX fd semantics over ESP-IDF VFS

- **Type:** feature (Track B PAL / ESP-IDF)
- **Status:** ~~unfinished — blocked-by bug-a-emit-obj-ignores-external-name-and-emits-the-pascal-identifier; the fs-c3 baseline is landed and independent of it~~
  **NOT BLOCKED. Re-claimed 2026-09-23 by frankS.** That blocker reached `done/`
  on 2026-09-02. The summary above has said so for three weeks while this line
  kept saying the opposite — and this line is the one a reader reaches first.
  `tools/progress.sh check` has been reporting it as STALE-PARK the whole time.
- **Owner:** frankS
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

PARK CONDITION SUPERSEDED 2026-09-23 — there IS a qemu/IDF runner now; see
the 2026-09-23 section at the end. The block below is kept as the record.

Acceptance is a C3/S3 link-and-run smoke; there is no device and no qemu/IDF
runner in this lane. External constraint, so `blocked/` rather than backlog.

One thing IS doable without hardware and is worth doing first when this resumes:
host-side `--platform=esp` tests that pin the CURRENT behaviour — `PAL_OPEN_EXCL`
returning `PAL_ERR_UNSUPPORTED`, and the errno collapse — so the rewrite has a
baseline to diff against instead of changing semantics blind.

## Moved to blocked/ 2026-07-31 (Track B sweep) — same wall as the rest of the ESP family

PARK CONDITION SUPERSEDED 2026-09-23 — every fact in this block has flipped.
It was re-checked and correct when written; see the 2026-09-23 section at the end.

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


## 2026-08-30 (pxx-b) — the block is gone, and the proposed hardware-free step was VACUOUS

Two findings, both measured.

### 1. There is a QEMU/IDF runner, and VFS file I/O works on it

Both `blocked/` moves above rested on "no qemu/IDF runner in this lane", checked
with `command -v qemu-system-riscv32`. That returns nothing and means nothing:
IDF installs its tools off PATH under `~/.espressif/tools/`, reachable only once
`export.sh` is sourced. Full write-up in [[feature-esp-peripheral-callback-api]].

VFS was then MEASURED rather than assumed from CLAUDE.md's "sockets and basic
VFS file I/O are what work" — that sentence describes the PAL's refusal list,
not what QEMU emulates, and on this same emulator the GPIO input path is
unmodelled and the first ADC call hangs. File I/O is genuinely real:

```
PROBE: fat_mount rc=0
PAL: open-create ok
PAL: write n=7 / seek rc=0 / read n=7 / content-mismatches=0 / close rc=0
PAL: open-EXCL=-38 (today: -38 unsupported)
PAL: open-missing=-1 (today: -1, errno collapsed)
```

So this ticket's acceptance — "an ESP-IDF link/run smoke on C3" — is attainable
here for the file-semantics half. C3 only; S3/xtensa is a separate boot on a
separate QEMU binary and is NOT covered.

### 2. The "one thing doable without hardware" cannot detect what it asserts

The 2026-07-20 note proposed host-side `--platform=esp` tests pinning
`PAL_OPEN_EXCL -> PAL_ERR_UNSUPPORTED` and the errno collapse, as a baseline to
diff a rewrite against. Measured on the host:

```
plain =-38
create=-38
excl  =-38
```

`PXX_PAL_ESP_IDF_TARGET` is set by `{$ifdef CPU_XTENSA}` / `{$ifdef CPU_RISCV32}`
inside `platform_backend.pas`, so an x86-64 build has NO file backend and every
call returns unsupported. A host assertion that EXCL is refused is therefore
green whether or not the refusal exists — and would stay green after someone
implemented EXCL, which is the precise opposite of a baseline. It cannot fail in
the direction that matters.

What makes the on-target version worth something is the row above it:
`open-create` **succeeds in the same run**. That success is the control; it
proves the backend is present, so the `-38` on the next line is a refusal rather
than an absence. Same assertion, opposite value, and the difference is entirely
the control sharing the run.

### Landed

`examples/esp32/fs-c3` — mounts FAT (custom `partitions.csv`; the stock
single-app table has nowhere to mount), drives the real PAL, and
`build.sh qemu-assert` pins all nine rows. It FAILS when EXCL or the errno
collapse moves, which is intended: if they moved because this ticket landed, the
new values are the deliverable and `want=` gets updated deliberately; if the
create/write/read rows broke instead, the PAL file path regressed. The failure
text says which.

### Still open — the actual rewrite

Unchanged and untouched by the above: direct `open`/`read`/`write`/`close`,
errno-style negatives, `PAL_STDIN`/`STDOUT`/`STDERR` mapping, exact
create/exclusive/truncate/append. The `read`/`write` Pascal-keyword collision
recorded in the ticket body is the first design fork; if the answer is a
compiler-supported external alias, that is a **Track A ticket**, not something
to build around in the PAL.

The baseline now exists to diff that work against, which was the point.

## 2026-08-30 (pxx-b) — parked to unfinished/, blocked on a Track A bug the fork turned out to BE

The `read`/`write` keyword collision in this ticket's body proposes two options:
"imported C declarations with safe Pascal names, or a compiler-supported
external symbol alias that preserves the local Pascal identifier".

Checked before filing a decision ticket, and the answer is neither: **the alias
already exists and does exactly this.** `external name 'sym'` is parsed today,
and `pasparser_proc.inc` documents precisely the required semantics — the link
symbol changes, the Pascal identifier does not.

It is **ignored by `--emit-obj`**, which is the only path ESP uses:

```
$ pxx --target=riscv32 --platform=esp --emit-obj alias_esp.pas alias_esp.o
$ readelf -sW alias_esp.o | awk '$7=="UND"{print $8}'
PalSysOpen   PalSysRead   PalSysWrite      <-- wanted: open / read / write
```

The same source built as a host executable emits a dynamic import named `write`
and fails with `undefined symbol: write`, so the dynamic path DOES honour the
clause. One back end applies it, the other silently drops it — and it is not
ESP-specific; x86-64 and hosted riscv32 `--emit-obj` do the same.

So this is not a language-surface decision for Track U and not a feature request:
it is [[bug-a-emit-obj-ignores-external-name-and-emits-the-pascal-identifier]],
filed for Track A with the repro and a regression that fails today.

**Not worked around.** Renaming the C side or routing the PAL past the collision
is the compiler-appeasement pattern CLAUDE.md forbids, and it would look like
progress while hiding an object-writer bug that affects every consumer of
`--emit-obj`, not just this PAL.

### Done and staying done

`examples/esp32/fs-c3` — the on-target baseline, nine rows pinned, C3 only. It
does not depend on the rewrite and is useful now: it is what the rewrite will be
diffed against.

### Not done

The rewrite itself. It resumes when the Track A bug lands.


---

## 2026-09-02 (frankH) — unblocked; baseline landed, but NOT the one this ticket asked for

`bug-a-emit-obj-ignores-external-name-and-emits-the-pascal-identifier` is in
`done/`, so the frontmatter edge is cleared. Acceptance is unchanged: it needs a
C3/S3 link-and-run and there is no device here.

### The "doable without hardware" note was pointing at the wrong population

The 2026-07-20 sweep note says to write host-side `--platform=esp` tests pinning
today's behaviour — `PAL_OPEN_EXCL` returning `PAL_ERR_UNSUPPORTED`, and the
errno collapse — so the rewrite has something to diff against. **Measured, and
that would have pinned the stub.** The entire stdio/IDF implementation in
`lib/rtl/platform/esp/platform_backend.pas` sits under
`{$ifdef PXX_PAL_ESP_IDF_TARGET}`, which lines 160–161 define **only** for
`CPU_XTENSA` and `CPU_RISCV32`. On x86-64 with `--platform=esp` that arm is
compiled out entirely:

| call | host `--platform=esp` | host POSIX |
| --- | --- | --- |
| open a missing path | `-38` | `-2` (ENOENT) |
| open with `EXCL` | `-38` | `3` |
| write to fd 1, len 0 | `-38` | `0` |
| read from a bad fd | `-38` | `-9` (EBADF) |

Everything is `-38`, including the plain open the real arm would have
**succeeded** at. So a host row asserting `-38` passes before and after the
rewrite and says nothing about either — and the errno collapse the note names
cannot be observed on the host at all, because the code that collapses it is
not in the binary.

### What landed instead

`test/esp_pal_fdsem_baseline.pas`, built for **riscv32 and xtensa** with
`--emit-obj`, where the real arm is what compiles. The load-bearing assertion is
the **symbol import**: the object must reference all seven newlib stdio entries
(`fopen fread fwrite fseek ftell fflush fclose`) the current implementation is
written on. That pins "still the stdio-backed path", and it is precisely what
must change when the rewrite moves to direct `open`/`read`/`write` — so the row
is **meant to go red then** and be updated deliberately, rather than keep
passing while the thing it names is gone.

**Negative control, run rather than assumed:** the same source built for the
host with `--platform=esp` references **0** of those 7, while both ESP targets
reference **7**. So the row discriminates which arm compiled instead of merely
observing that something built. Wired into `test-emit-obj` beside the other ESP
object rows.

### Still needs hardware

Everything in Acceptance. This only ensures the code the rewrite will edit is
proven to compile, and that its current shape is recorded in a way that will
notice when it changes.

---

## 2026-09-23, frankS — RE-CLAIMED. The wall is down and the harness already exists. NOT IMPLEMENTED.

Measured at `434cc8f7f`, `compiler/pascal26` `d410fb592c39`, on plexus.

### What actually changed, and none of it was recorded here

**1. The blocker closed three weeks ago.** `bug-a-emit-obj-ignores-external-name-and-emits-the-pascal-identifier`
reached `done/` on 2026-09-02. That is the whole of what the "Problem" section
says is missing — *"a compiler-supported external symbol alias that preserves
the local Pascal identifier"* — which is what the direct `open`/`read`/`write`/
`close` binding needs, `read` and `write` being Pascal keyword tokens. The
summary has said UNBLOCKED since then; the **Status line** kept saying
blocked-by, and the Status line is what a reader reaches first.

**2. "Acceptance still needs a C3/S3 link-and-run, which this box cannot do" is
false, and was false when written.** Measured, not read:

```
$ cd examples/esp32/fs-c3 && . ~/esp/esp-idf/export.sh && ./build.sh qemu-assert
OK   fs-c3 -- ESP PAL file I/O works on target; EXCL and errno gaps pinned
rc=0
```

A real ESP-IDF link, merged flash image, booted on **esp32c3 under the
Espressif qemu fork**, output diffed against a stored baseline.

**SAY WHICH QEMU, because there are two on this box and they disagree.** This
ran Espressif's `qemu-system-riscv32`
(`~/.espressif/tools/qemu-riscv32/esp_develop_9.2.2_20250817/`), not a stock
system qemu. The distinction is not pedantry: frankb-8e measured the same week
that stock `qemu-xtensa` implements `MUL32_HIGH` in NO core model and SIGILLs on
an ordinary integer multiply, while Espressif's `qemu-system-xtensa -M esp32s3`
has it (`bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it`,
p40). So "this box cannot run it" can be true of one qemu and false of the
other, and a bare `qemu` in a park note does not say which was tried. Same
which-instrument axis as the objdump-versus-llvm-objdump split on plexus/borg. IDF is v6.0.1 at
`~/esp/esp-idf`; both Espressif qemus are installed. It is wired into
`make test-esp-idf` and has been running there.

**3. The acceptance harness was built FOR this ticket and nobody told the
ticket.** `fs-c3`'s assertion pins exactly the two rows in the Problem list:

```
PAL: open-EXCL=-38 (today: -38 unsupported)
PAL: open-missing=-1 (today: -1, errno collapsed)
```

and its failure text says, in its own words, *"If open-EXCL or open-missing
moved, that is feature-pal-esp-posix-fd-semantics landing and the new values are
the point -- update want= deliberately."* The baseline this ticket's 2026-07-20
park asked someone to build first — *"so the rewrite has a baseline to diff
against instead of changing semantics blind"* — **exists, runs, and names this
ticket.**

### Why this sat still: three independent records, each true when written

The July parks were re-checked and correct on their dates (no qemu, `IDF_PATH`
unset, no board). The environment moved underneath all three and **nothing
re-reads a park** — a park has no owner and no instrument watching it, which is
precisely what `tools/progress.sh check`'s STALE-PARK aperture exists for. It
*has* been reporting this ticket, and that report is how I found it: it names
the prose blocker, not the environment claim, so the environment claim was still
mine to measure. **The checker found the half it can see; the half it cannot see
was the bigger one.**

### What I did NOT do, stated plainly

**No implementation.** The backend is still newlib stdio
(`lib/rtl/platform/esp/platform_backend.pas`, `PalBackendOpen` and its family,
all under `{$ifdef PXX_PAL_ESP_IDF_TARGET}`), `PAL_OPEN_EXCL` still returns
`PAL_ERR_UNSUPPORTED` at the top of `PalBackendOpen`, and the errno collapse is
untouched. I re-claimed and removed the reasons this could not be started; I did
not start it.

### For whoever takes it

- The rewrite is stdio -> direct POSIX `open`/`read`/`write`/`close`/`lseek`
  over IDF VFS, bound with `external name` so the Pascal-keyword spellings of
  `read`/`write` stop being the obstacle.
- **Do not host-test it.** The whole IDF arm is behind
  `{$ifdef PXX_PAL_ESP_IDF_TARGET}` (CPU_XTENSA / CPU_RISCV32 only), so a
  host-side `--platform=esp` row pins the STUB and passes identically before and
  after the rewrite. This ticket's own summary already warned about that and it
  is the trap here.
- Move the two pinned rows in `examples/esp32/fs-c3/build.sh`'s `want=` in the
  same commit as the behaviour, deliberately — the script asks for exactly that.
- **The S3 arm is still unmeasured and is the honest gap in this update.**
  `fs-c3` is C3-only; there is no `fs-s3`. Acceptance names C3 *and* S3, so
  half of it has a runner and half does not, and I am not claiming otherwise.
  This is the same one-target hazard that cost two other ESP tickets this week —
  an effect measured on one chip and written up as a property of the platform.
