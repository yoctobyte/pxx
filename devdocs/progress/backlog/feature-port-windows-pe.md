---
summary: "Windows/x64 target — PE/COFF writer, MS x64 ABI, IAT imports; testable via Wine"
type: feature
prio: 45
blocked-by: [feature-port-rtl-over-libc]
---

# Windows native target (x64) — new PE format + MS x64 ABI

- **Type:** feature (Track A — new object format + ABI + linking). Portability campaign.
- **Status:** backlog (blocked on [[feature-port-rtl-over-libc]])
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Full map in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).

## Cost is Axis B (format), not Axis A

Windows never allows raw syscalls (numbers change every build); the boundary is
ntdll/kernel32. The library-call *concept* is [[feature-port-rtl-over-libc]]; the
*work* is a **brand-new PE/COFF writer** — pxx only writes ELF today.

## What's new

1. **PE/COFF writer** — the big rock. Headers, sections, base relocations, entry point.
2. **IAT/ILT import tables** — the PE analogue of ELF `DT_NEEDED` (hint/name tables,
   import directory) to bind kernel32/ntdll **exports** (CRT-free — see Strategy; no
   msvcrt/ucrt).
3. **Microsoft x64 calling convention** — NOT "stdcall" (stdcall is Win32-only; on
   Win64 all conventions collapse into one). Args in **RCX/RDX/R8/R9**, mandatory
   **32-byte shadow space** reserved by the caller, different callee-saved set than
   SysV, table-based unwind (`.pdata`/`.xdata`, `RtlAddFunctionTable`). This is a
   codegen ABI variant on top of the existing x64 backend.
4. RTL primitives lower to kernel32/ntdll calls (via [[feature-port-rtl-over-libc]]).

## Strategy — CRT-free, thin kernel32/ntdll binding (the correct minimization)

The tempting dodge — "raw syscalls, avoid the fat DLL" — **does not work on Windows and
must not be attempted.** Windows syscall numbers change every build/version, are
undocumented, and unstable by design; the *only* stable interface is ntdll (Microsoft's
own thin `syscall` wrapper). A direct-syscall binary breaks on the next Windows update
(it's what malware does to dodge EDR, and it notoriously shatters across versions), and
Wine implements the DLL *exports*, not the raw NT syscall instruction — so direct
syscalls fail the test path too.

The layer intuition is inverted: **ntdll is the thinnest, most stable layer, not the
fat one.** The incompatibilities live *above* it (msvcrt/ucrt versions, the CRT
startup, SEH). So the minimization — the libc-free-equivalent on Windows — is:

- **Bind kernel32 (or ntdll) directly for ~10 primitives** — `GetStdHandle`,
  `WriteFile`, `ReadFile`, `VirtualAlloc`/`VirtualFree`, `ExitProcess`, `CreateFileW`.
  Documented, thin, Wine-faithful. (kernel32 is the pragmatic pick — documented Win32;
  ntdll is even thinner but needs manual `NTSTATUS`/`UNICODE_STRING`/`OBJECT_ATTRIBUTES`
  handling. Start kernel32, drop to ntdll only to shave further.)
- **Skip the CRT entirely** — no msvcrt/ucrt, no `mainCRTStartup`. Own PE entry point
  (`_start`) does RTL-init → program → `ExitProcess`. This is where most "many issues"
  come from; not linking the CRT dodges them.

This makes Windows just **rtl-over-libc with a Windows binding** ("libc" = the platform's
thinnest stable DLL — the same abstraction as libc.so on OpenBSD / libSystem on macOS).
The ticket is big because of **PE format + MS x64 ABI**, NOT because of runtime surface —
the runtime shrinks to a ~10-symbol import table. Bind ntdll/kernel32 **exports** via the
IAT, never the raw syscall instruction.

## Testing is cheap — Wine

Test bed: [[feature-t-windows-wine-harness]] (wine runner + mingw-w64 oracle), and this
sits under umbrella [[feature-port-multi-os-abstraction]].

`wine out.exe` on Linux runs user-mode PE hitting kernel32/ntdll/msvcrt faithfully —
**no Windows VM needed**. Wine gives the loader + DLL resolution free. So Windows is
*cheaper to test than to implement*: the PE writer + MS x64 ABI is real work, but the
oracle is one command. **No code-signing needed** — Windows runs unsigned user exes
(unlike macOS).

## Acceptance

- `--platform=windows` emits a PE/x64 exe that runs under **Wine** and produces output
  byte-identical to the reference for a scalar + heap/string/exception torture program.
- MS x64 ABI verified by calling a kernel32/CRT function with >4 args (shadow space +
  stack args exercised).
- Gate: `make test` + self-host byte-identical (ELF default untouched); Wine smoke.

## Scope note

Assume **Win64** only. Win32 (`stdcall`, `int 2e`) is out of scope unless a concrete
need appears.
