---
summary: "RTL-over-libc lowering mode — route runtime primitives through a system C library instead of raw syscalls"
type: feature
prio: 55
---

# RTL-over-libc — the portability force multiplier

- **Type:** feature (Track A — RTL lowering / codegen / linking). Portability campaign.
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-17, from the OS-portability mapping session. Full analysis in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).
- **Related / unblocks:** [[feature-port-openbsd-libc]] (falls out immediately),
  [[feature-port-windows-pe]] (same "call the system lib" lowering, + PE writer),
  [[feature-port-macos]] (blocked on hardware, but same lowering). Sibling:
  [[feature-port-freebsd-native]] (the raw-syscall path that does NOT need this).
  North star: [[ir-as-substrate]].

## Why

pxx is libc-free on Linux because Linux has a stable, public raw-syscall ABI — the
**exception** among OSes. Every other mainstream OS (OpenBSD, macOS, Windows) makes a
**system C library** the supported kernel boundary. The generalizable capability that
unlocks all of them is **one lowering mode**, not per-OS special cases:

> Wire the RTL primitives (`write`/`read`/`open`/`mmap`/`munmap`/`exit`/`brk`/
> `nanosleep`/…) to **C-library entry points** (`write(2)`, `mmap(3)`, `_exit`, …)
> instead of emitting the raw `syscall` instruction.

pxx already dynamic-imports external `.so`s through the PLT (the C frontend links C
libraries; `elfwriter.inc` emits `PT_DYNAMIC`/`DT_NEEDED`/interp). So this is *wiring
existing machinery to the RTL's own primitives*, not a new subsystem.

## Design

- A platform/ABI switch (`--platform=<os>` or the existing PAL axis — see
  [[project_pal_platform_axis_step1]]) selects **syscall-emit** vs **libc-call** for
  the RTL primitive set.
- In libc-call mode, each primitive lowers to a call to the named libc symbol
  (imported via `DT_NEEDED libc.so` + PLT), with the platform's C ABI (SysV amd64 on
  ELF platforms; MS x64 comes with [[feature-port-windows-pe]]).
- Error convention becomes libc's: `-1` + `errno` (TLS `__errno_location`) instead of
  Linux's negative-rax — the RTL's error checks branch on the mode.
- Keep the primitive *set* identical; only the lowering of each changes. Everything
  above the primitives (managed strings, heap, exceptions) is untouched.

## The switch reaches UP into codegen, not just the RTL library (2026-07-21 scout)

Sizing the Windows target surfaced a subtlety worth pinning here: raw `syscall` lives in
**two** places, and the lowering switch must cover both — it is not purely an
`lib/rtl/*` edit.

1. **RTL primitives (the library half — expected).** `lib/rtl/pxxcio.pas` is the single
   IO chokepoint (fd 1, `__pxxrawsyscall`), plus `ansiterm.pas:192`. libc/kernel32 mode
   swaps these. Straightforward.
2. **Emitted program startup (the codegen half — easy to miss).** The compiler emits a
   raw `syscall` instruction into the program's **own `_start` stub**:
   `compiler/emit.inc:116` `EmitwriteSyscall` (i386 `int 0x80` `:118`, aarch64 `svc`
   `:105`), `EmitSyscall`=`0F 05` at `emit.inc:80`, `SYS_WRITE=1` at `defs.inc:601`.
   This is **codegen**, below the RTL — in libc/DLL mode it must emit a `CALL` to an
   imported symbol (Windows: `kernel32!WriteFile`/`ExitProcess`, needing the
   [[feature-port-windows-pe]] IAT), not a `syscall`. So the flag threads into `emit.inc`,
   not only `lib/rtl`.
3. **Bypass modules (out of THIS ticket's primitive set — flag separately).**
   `lib/rtl/palthread.pas`, `palsync.pas`, `baseunix.pas:122`, `random.pas:225` call
   `__pxxrawsyscall` directly (clone/futex/mmap/getrandom/termios), bypassing pxxcio.
   These are a per-OS **model** port, not a lowering flip (futex ≠ Win events), and are
   deferred — Windows single-threaded first (see [[feature-port-windows-pe]]).

The "zero `syscall` instructions" acceptance grep below already implies #2; this note
just names *where* so the implementer patches `emit.inc` and doesn't stop at `lib/rtl`.

## Acceptance

- With libc-call mode on for a Linux host (proving the mode against a known-good
  kernel *before* trusting it on a new OS), a hello-world + a heap/string/exception
  torture test produce **byte-identical program OUTPUT** to the raw-syscall build.
- The emitted binary contains **zero `syscall` instructions** (all kernel access via
  libc PLT) — verify with a disassembly grep. This is the property that makes
  [[feature-port-openbsd-libc]] compliant with `pinsyscalls` by construction.
- Gate: `make test` + self-host byte-identical (raw-syscall mode is the default and
  must stay bit-for-bit unchanged — libc mode is opt-in behind the flag).

## Notes

- **This does not replace raw syscalls.** Linux and FreeBSD stay raw-syscall (their ABI
  rewards it, keeps the libc-free identity). libc mode is for the OSes that mandate it.
- Land incrementally behind the flag; never a long-lived branch (same discipline as the
  experimental frontends).
