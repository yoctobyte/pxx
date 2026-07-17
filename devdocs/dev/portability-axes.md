# OS portability axes — what it actually costs to add a target OS

Scope: adding a **new operating system** as a pxx target (FreeBSD, OpenBSD, macOS,
Windows), *not* a new CPU (that's the cross-target backend work). The cost is almost
never where intuition puts it. This note exists so the analysis isn't re-derived —
and so nobody prices OpenBSD like Windows again.

Companion notes: [`ir-as-substrate.md`](ir-as-substrate.md) (why one core capability
beats N special cases) and [`c-linking-and-crtl-autopull.md`](c-linking-and-crtl-autopull.md)
(the external-`.so` linking pxx already does).

## Two independent axes

A target OS varies along two axes that do **not** move together:

- **Axis A — how you reach the kernel.** *Raw syscalls* (the process issues the
  `syscall` instruction itself) vs *through a system library* (you call a libc/DLL
  entry point and it syscalls for you).
- **Axis B — executable/object format.** ELF vs Mach-O vs PE/COFF.

**Linux is the exception, not the rule.** pxx is libc-free on Linux only because Linux
has a *stable, public, forever* raw-syscall ABI. Almost every other mainstream OS
declares a **system library** to be the supported boundary and reserves the right to
change syscall numbers underneath it.

| OS | Axis A (kernel reach) | Axis B (format) | raw syscalls allowed? |
| --- | --- | --- | --- |
| Linux | raw syscall | ELF | ✅ blessed, ABI stable forever |
| FreeBSD | raw syscall | ELF | ✅ works (own table; **error via carry flag**, not neg-rax) |
| OpenBSD | **via libc.so** | ELF | ❌ killed by `pinsyscalls` unless the site is pinned |
| macOS | **via libSystem.dylib** | Mach-O | ❌ syscall numbers deliberately unstable |
| Windows | **via ntdll/kernel32** | PE/COFF | ❌ syscall numbers change every build |

## Three distinct reasons an OS forces you off raw syscalls

"Go through the library" is one outcome with three orthogonal causes — do not conflate
them (Windows and OpenBSD arrive there by different roads):

| reason | OS | can you pin/hardcode numbers? |
| --- | --- | --- |
| **none** — table is a stable public contract *and* raw sites are permitted | Linux, FreeBSD | n/a — just issue the syscall |
| **policy** — numbers are stable, but the kernel kills raw `syscall` *sites* not in libc (`pinsyscalls`) | OpenBSD | yes, but forbidden anyway → go through libc |
| **instability** — the syscall numbers themselves move between builds | **Windows**, macOS | **no** — can't even hardcode them |

Key asymmetry, because it reads counter-intuitive: **Linux is NOT "on par with NT".**
Both kernels have a `syscall` mechanism, but their *stability posture is opposite* on
the only axis that matters — *is the syscall table a public contract?* Linux: yes,
append-only forever, numbers never reused ("we do not break userspace"). FreeBSD: yes,
append-only + versioned COMPAT shims. **Windows: no** — the SSDT (System Service
Descriptor Table) is a private implementation detail Microsoft reshuffles at will;
insert a syscall in the middle and every SSN after it shifts. Public evidence:
j00ru's NT syscall-number tables spanning Win2000→Win11 show the same call (e.g.
`NtCreateFile`) with different SSNs across releases and even across Win10 feature
updates. NT's public contract is **ntdll**, one layer up — not the kernel.

Corollary: even direct-syscall Windows tooling (malware, "Hell's Gate" red-team code)
**cannot escape ntdll** — it resolves the *current* SSN by parsing ntdll's stubs at
runtime rather than hardcoding it. So on Windows you bind ntdll/kernel32 regardless;
hardcoding SSNs is the one approach that is actually wrong. (And Wine tests DLL exports,
not raw SSNs — settling it for our test path too.)

## What pxx already has (2026-07)

- **ELF, both flavors:** static raw-syscall binaries *and* dynamically-linked binaries
  that import external shared objects. `elfwriter.inc` emits `PT_DYNAMIC`,
  `DT_NEEDED`, the interp (`/lib64/ld-linux-x86-64.so.2`), and calls into `libNAME.so`
  through the PLT — this is how the C frontend links C libraries today.
- **No Mach-O writer. No PE writer. No code-signing.**

So "call a function in an external system library" is a **solved, shipping**
capability — not new work. The cost of a new OS is therefore almost entirely
**Axis B (new object format?) + code-signing (macOS only)**, *not* Axis A.

## The cost table (the one to remember)

| target | kernel reach | format | new work | size | how to TEST |
| --- | --- | --- | --- | --- | --- |
| Linux | raw syscall | ELF ✓ | — | done | native |
| **FreeBSD** | raw syscall | ELF ✓ | syscall table + carry-flag convention + ELF brand (OSABI/note) | **small** | qemu image; **linuxulator runs today's pxx binaries unmodified** |
| **OpenBSD** | via libc.so | ELF ✓ | route RTL through libc (reuses existing `.so` import path); swap interp to `/usr/libexec/ld.so` | **small** | qemu (autoinstall) |
| **macOS** | via libSystem | **Mach-O ✗** | new object format + **mandatory code-signing** + must dynamic-link libSystem (no static libc) | **large** | ❌ needs real Apple hardware (`darling` immature; qemu-macOS license-gray) |
| **Windows** | via ntdll/k32 | **PE/COFF ✗** | new object format + **IAT/import tables** + **MS x64 ABI** (see below) | **large** | **Wine on Linux — `wine out.exe`, no VM** |

Read it as: **FreeBSD and OpenBSD are both "small" — they're ELF, which pxx already
writes and already dynamic-imports.** macOS/Windows are "large" because each needs a
*brand-new object-format writer*. Signing is macOS's *extra* tax on top of its
new-format tax. The library-loading *concept* OpenBSD shares with Windows is Axis A
and is cheap; the *work* is Axis B and OpenBSD doesn't need any.

## The force multiplier: an RTL-over-libc mode

The generalizable capability is **not** "OpenBSD support." It is an RTL lowering mode
that wires the runtime primitives (`write`/`read`/`mmap`/`exit`/…) to **C-library
entry points** instead of to raw `syscall` emission. Build it once and:

- **OpenBSD falls out immediately** (same ELF writer, `DT_NEEDED libc.so`).
- It is the prerequisite mindset for macOS/Windows — those add only their native
  object-format writer on top of the same "call the system lib" lowering.

This is the `ir-as-substrate` north star applied to the OS axis: one core capability,
N platforms. Keep raw syscalls for the two OSes that reward it (Linux, FreeBSD); build
**one** RTL-over-libc mode as the door to everything else.

## Why OpenBSD forbids raw syscalls (it is not "pointless", and it is not signing)

Recorded because it reads like gratuitous obstruction from the libc-free side, and it
isn't. The mechanism (`msyscall(2)`, 6.4 → `pinsyscalls`, 7.3/7.4) is **syscall
call-site allowlisting**, an **anti-ROP** measure — *no cryptographic signature is
involved*:

- The kernel knows the exact address(es) from which each syscall number may be issued
  (libc's pinned stubs). A `syscall` from anywhere else → immediate `SIGABRT`.
- This kills ROP/JOP chains that pivot to a `syscall` gadget: even with full IP
  control from a bug, an attacker cannot reach the kernel from the program's own text.

The benefit is **smaller** for a tiny static libc-free binary (no dynamic loading,
small text, W^X already) — but **non-zero**: a bug in pxx's *own* emitted code could
still ROP to pxx's *own* syscall gadgets, which pinning stops. So the honest position:
OpenBSD's design is a defensible defense-in-depth tradeoff Linux chose not to make. The
pxx objection is **philosophical** ("don't force a userland lib we deliberately do
without"), not a proof the mechanism is useless. Going **through libc satisfies
pinsyscalls by construction** — pxx emits zero `syscall` instructions; every syscall
originates inside OpenBSD's own libc, which is exactly and only what the kernel
permits. The wasp's nest exists only if you insist on staying libc-free *there*.

## Windows specifics (assume Win64)

- **No `stdcall` on Win64.** cdecl/stdcall/fastcall all collapse into the single
  **Microsoft x64 calling convention**: integer args in RCX/RDX/R8/R9, a mandatory
  **32-byte shadow space** the caller reserves, a different callee-saved register set
  than SysV, and table-based unwind (`RtlAddFunctionTable`/`.pdata`). What pxx lacks is
  this ABI variant, *not* "stdcall" — stdcall only exists on 32-bit Windows.
- **Imports** are PE **IAT/ILT** (hint/name tables), a different on-disk structure than
  ELF `DT_NEEDED` — the concept transfers, the format is new.
- **Signing** is *not* required to run a user exe (SmartScreen only nags downloaded
  ones). Contrast macOS.

## macOS specifics

- **Mach-O** object format (new writer).
- **Mandatory code-signing on Apple Silicon** — even an ad-hoc signature
  (`codesign -s -`) is required or the kernel refuses to `exec`. Not optional.
- **No static libSystem** — Apple removed it; you *must* dynamically link libSystem,
  and libSystem *is* the only supported syscall boundary (numbers change between
  releases).
- **Testing is the real blocker:** no cheap, legal emulation. `darling` (a Wine-like
  translation layer) is far less mature than Wine, especially on Apple Silicon;
  qemu-macOS is license-gray and painful. Realistically needs Apple hardware — which
  is why macOS ranks last independent of implementation effort.

## Recommended order

1. **FreeBSD** — small, stays in the libc-free family (raw syscalls), and linuxulator
   gives a zero-work smoke *today*. Highest signal per hour.
2. **RTL-over-libc mode** — the force multiplier. Building it lands **OpenBSD** almost
   for free and is the foundation for the rest.
3. **Windows** — new PE writer + MS x64 ABI, but testable cheaply via **Wine** (no VM).
4. **macOS** — last: large implementation *and* untestable without Apple hardware.

Precedent for the whole split: **Go** was forced through libSystem on macOS and libc on
OpenBSD, while keeping raw syscalls on Linux (and historically FreeBSD) — the same
raw-vs-libc line this note draws.
