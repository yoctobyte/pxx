---
summary: "RTL-over-libc lowering mode — route runtime primitives through a system C library instead of raw syscalls"
type: feature
prio: 55
---

# RTL-over-libc — the portability force multiplier

- **Type:** feature (Track A — RTL lowering / codegen / linking). Portability campaign.
- **Status:** unfinished — PARKED 2026-08-17 by frank2 at a green point;
  acceptance instrument landed, no compiler changes made. See the dated note below.
- **Owner:** frank2
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

## 2026-08-17 (frank2, Track A) — PARKED after landing the acceptance instrument. No compiler changes in the tree.

Stopped deliberately at a green point rather than pushing a codegen change
through overnight. **Nothing is half-applied**: the only thing landed is a new
tool, so `master` is clean and the self-host gate is untouched.

### The acceptance criterion as written cannot fail — fixed first

> *"The emitted binary contains zero `syscall` instructions — verify with a
> disassembly grep."*

The obvious spelling of that is:

    objdump -d <binary> | grep -c syscall

and it prints **0 for every pxx binary ever built**, including one making 57 raw
syscalls. pxx writes ELFs with **program headers only and no section headers**,
and `objdump -d` disassembles *sections*. It does not error or produce visibly
empty output — it prints a three-line header and a zero.

So this ticket's acceptance test would have passed on day one and kept passing
no matter what the compiler did. Caught only because I checked whether the
instrument could distinguish a raw build from a libc one *before* trusting it —
today's recurring lesson arriving a fourth time.

**Landed `tools/syscall_scan.py`**: reads the program headers directly,
disassembles each executable `PT_LOAD` as raw bytes at its true vaddr, counts
the kernel-entry mnemonic for the ELF's own `e_machine`, and **refuses to report
a count it could not measure** (no exec segment, unknown machine, empty
disassembly are all errors, never 0). Per-arch mnemonics, because the
instruction is only spelled `syscall` on x86-64 — grepping that word alone
reports a clean zero on every cross target, the same silent pass one level down.

Measured baselines to work against:

| binary | kernel-entry instructions |
| --- | ---: |
| pxx hello-world (`WriteLn`) | **57** |
| pxx + one `external 'libc.so.6'` call | 55 |
| `/bin/true` (ordinary libc-linked binary) | **0** |

`/bin/true` at 0 is the control worth keeping: it is the target state, and it
proves the tool does not simply always find syscalls.

### Sizing — what is and is not ready

**Already works, measured:** a Pascal program can call libc through the PLT
today with no compiler change at all —

```pascal
function libc_write(fd: Integer; buf: Pointer; n: PtrUInt): PtrInt;
  cdecl; external 'libc.so.6' name 'write';
```

compiles, links, and runs. So the import machinery this ticket assumed is
genuinely present and does not need building.

**The real chokepoint is narrower and better than the ticket's plan.** All 62
`__pxxrawsyscall` call sites across 11 RTL units funnel through ONE intrinsic →
`AN_SYSCALL` → **`IR_SYSCALL`, a single IR op with an arg chain**
(`ir.inc:6107`). Lowering *that* to a libc call covers every RTL primitive at
once **without touching `lib/rtl` at all** — which is strictly better than the
ticket's per-primitive mapping and much smaller.

Suggested shape for whoever continues, not yet implemented:

- lower `IR_SYSCALL` in libc mode to a call of libc's `syscall(3)` — the
  signature is a 1:1 match (`long syscall(long nr, ...)`);
- **keep the raw error convention** by mapping libc's `-1`/`errno` back to
  `-errno` at that one site. Then no RTL error check changes, and program output
  is byte-identical by construction rather than by inspection;
- `emit.inc`'s `_start` stub (`EmitwriteSyscall`, `SYS_EXIT_GROUP` at `:225`)
  is the separate half the ticket already flags, and is what stands between 55
  and 0.

**The unsized piece, and why I stopped:** in libc mode the compiler must emit
PLT imports for `syscall` (and `__errno_location`) that **no Pascal `external`
declared**, i.e. synthesise a dynamic import from codegen. I could not size that
confidently tonight, and it is `emit.inc`/`elfwriter.inc` — Track A's most
gate-sensitive ground, with the self-host fixedpoint riding on it. Guessing at
it overnight is exactly the trade this ticket's own "land incrementally, never a
long-lived branch" note warns against.

### Also worth correcting in this ticket

The `--platform=` axis already exists (`PLATFORM_POSIX` / `PLATFORM_ESP`,
`compiler.pas:365`), so the switch is a new value on an existing axis, not a new
flag mechanism.

### Note on file ownership

`tools/syscall_scan.py` is new and is not in Track T's named set
(`testmgr.py`, `twatch*`, `fuzz.sh`, `pasmith*`, `tstate/**`) — it sits beside
the other general probes like `gcc_diff_probe.sh`. Flagged rather than assumed.

## Notes

- **This does not replace raw syscalls.** Linux and FreeBSD stay raw-syscall (their ABI
  rewards it, keeps the libc-free identity). libc mode is for the OSes that mandate it.
- Land incrementally behind the flag; never a long-lived branch (same discipline as the
  experimental frontends).
