---
track: A
prio: 65
type: bug
status: open
found: 2026-09-10
found-by: frankD
owner: ""
blocked-by: []
summary: "The first heap allocation in ANY pxx program maps HEAP_ARENA = 268435456 (256 MiB) in one MAP_PRIVATE|MAP_ANONYMOUS request with NO MAP_NORESERVE (builtinheap.pas:885, flags 0x22 at :1231), so a memory-capped guest or container refuses a mapping whose pages would never be touched and the program dies with `pxx: out of memory (heap arena mmap failed)` before doing any work. IT IS A RESERVATION, NOT USAGE, AND THE GAP IS 650x: a string-concat program peaks at 392 KB RSS and the compiler at 14764 KB compiling it, against 256 MiB demanded. Measured on the beta-0.1 minimal ISO, and it is WORSE than a compiler problem: the pxx-built BUSYBOX hits it too, so at 288 MB `ash` cannot start and PID 1 dies before /init runs a line -- the floor to BOOT A PXX USERLAND AT ALL and the floor to compile on it are the same floor, bracketed at 288 MB fails / 320 MB works (two independent signals, init banner and busybox's own ash banner; 320/384/448 all pass as the positive control). A program that allocates nothing makes no mmap call at all. This is the ONLY thing standing between the owner's stated beta-0.1 milestone (`a minimal system ... and it all fits in ~64MB of memory') and the actual footprint, which is ~15 MB."
---

# The heap arena reserves 256 MiB up front, and asks the kernel to commit it

Found while documenting the beta-0.1 minimal-Linux-system milestone (Track D),
measuring the owner's own claim that the system fits in ~64 MB of RAM. The system
does. The reservation does not.

## The mechanism

`compiler/builtin/builtinheap.pas`:

```
:885   HEAP_ARENA = 268435456;   { 256 MiB mmap chunk; anon pages fault in lazily }
:1231  prot=PROT_READ|PROT_WRITE=3, flags=MAP_PRIVATE|MAP_ANONYMOUS=0x22=34.
```

The comment is right that pages fault in lazily — and that is exactly why the
flags are wrong. `0x22` omits `MAP_NORESERVE` (`0x4000`), so the kernel's
overcommit heuristic is asked to account for a quarter-gigabyte that the program
has no intention of touching. On a box with headroom the heuristic waves it
through and nobody notices; on a small guest it refuses, and `HeapMmapFailed`
turns that into an immediate `OOM_MSG` exit.

## Measured, x86-64 Linux, 2026-09-10

| what | reserved | peak RSS |
| --- | --- | --- |
| `s := s + 'x'` 50 times | 256 MiB | **392 KB** |
| the pinned compiler compiling that program | 256 MiB | **14,764 KB** |
| `writeln` of a literal (no allocation) | *no mmap at all* | 392 KB |

`strace -e trace=mmap` shows exactly one `mmap(NULL, 268435456)` per allocating
process, and zero for the non-allocating one — so the arena is taken on first
allocation, not at startup, and the fix cannot break a program that never
allocates.

On the minimal ISO (`tools/mkminimal.sh --iso --batch`, boots and compiles a
Pascal program in the guest):

```
512 MB guest   MINIMAL-IMAGE OK
256 MB guest   pxx: out of memory (heap arena mmap failed)
               -> init exits 203 -> "Kernel panic - not syncing:
                  Attempted to kill init! exitcode=0x0000cb00"
```

**The failure signature is worth its own line, because it reads as a boot
failure rather than as an allocation failure.** The panic is the kernel's
correct report of PID 1 exiting; the cause is one refused `mmap` four lines
earlier in the log. Anyone testing this image on a small VM will read the panic
and go looking at the kernel, the initramfs, or the ISO.

(Below 128 MB a *different* failure comes first — `Initramfs unpacking failed:
write error`, because the uncompressed payload is 45,445,948 bytes and has to
live in RAM. That one is a genuine size floor and not this bug.)

## Why this is worth 60

It is not a crash in the compiler and nothing in the suite can see it — every
gate runs on a box with gigabytes free, so this defect is **structurally
invisible to the instrument that would normally catch it**, in the same way the
32-bit width bugs are invisible on x86-64. What it blocks is a stated release
claim: the owner's beta-0.1 keypoints (2026-09-10) include *"a minimal system.
with most unix tools (aka busybox) and a compiler. and self-host capability. and
it all fits in ~64MB of memory"*. The footprint supports that — 15 MB to compile
— and one constant refuses it.

It also bites any user running a pxx binary under a container memory limit,
which is why it is now documented in `docs/reference/limits.md` as a live limit
rather than left implicit.

## The fix, and the thing to decide

Two candidates, and they are not exclusive:

1. **Add `MAP_NORESERVE`.** One flag. Keeps the single-arena design and the lazy
   fault-in the comment already relies on. The behaviour change is that
   over-reserving no longer fails early — it fails at first touch instead, with a
   SIGSEGV rather than a message, which is why this is a decision and not
   obviously free.
2. **Retry smaller on failure.** `HeapMmapFailed` currently gives up; halving the
   request down to some floor would make the runtime adapt to the box it is on.
   Strictly more code, and it changes the arena invariant that `PXXAlloc` relies
   on (`HeapEnd := HeapPtr + arena`) — read :874's warning before touching it.

Whoever takes this should check the non-hosted arms first: `HEAP_ARENA` is
`65536` on ESP and `1048576` on wasm, both static BSS buffers, and neither goes
through `mmap` — so the change is confined to the hosted arm, but the constant is
shared and the `WasmArena` size comment at :874 says it MUST equal the byte size
of that array.

**Do not verify this on plexus alone.** A fix here passes trivially on any
developer box, including the broken version. The positive control is the 256 MB
guest above: it must go from the OOM message to `MINIMAL-IMAGE OK`.

## 2026-09-10, later — it is not the compiler, it is the USERLAND, and the floor is 320 MB

Filed above from the compiler's failure. Then measured the interactive image and
the finding got strictly worse: **the pxx-built BusyBox reserves the arena too.**

```
288 MB   banner=0 ash_banner=0 arena_oom=1 panic=1     <- PID 1 never runs a line
320 MB   banner=1 ash_banner=1 arena_oom=0 panic=0
384 MB   banner=1 ash_banner=1 arena_oom=0 panic=0
```

`/init` is an ash script and ash is busybox, which pxx compiled — so its first
allocation takes the 256 MiB arena before `/init` executes anything. At 288 MB
that mmap is refused, ash exits 203, and the kernel panics. **The floor to boot a
pxx-built userland at all is therefore the same floor as the floor to compile on
it**, and both are the arena rather than the payload.

Two independent signals per row, because one of them is unreliable on its own:
`/init`'s banner is echoed by ash and is LOST when init dies (buffered, and the
panic beats the flush), while busybox's own `built-in shell (ash)` line comes
from a different producer. 320/384/448 passing is the positive control — the
harness can report success.

**A correction to my own first reading, recorded because it is the more likely
mistake for the next person.** I first read the all-rows-fail result as a broken
harness — piped stdin hitting EOF — and it was not: the shell genuinely could not
start. The two look identical from outside, and the discriminator is the arena
message in the log, not anything about the pipe.

Raised 60 -> 65 on that basis: as filed this was "the compiler needs a big box",
which is a developer inconvenience. Measured, it is "a pxx-built userland cannot
boot on a small box", which is the thing the beta-0.1 milestone is about, and it
reaches every pxx-built program rather than just `pascal26`.
