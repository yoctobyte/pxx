---
summary: "Windows/x64 target — PE/COFF writer, MS x64 ABI, IAT imports; testable via Wine"
type: feature
track: M
prio: 25
blocked-by: []
---

# Windows native target (x64) — new PE format + MS x64 ABI

- **Type:** feature (Track A — new object format + ABI + linking). Portability campaign.
- **Status:** working: phase 1 landed 2026-11-14 (console, heap, exceptions, argv; Wine)
- **Owner:** the kernels session (BSD/Minix/OpenBSD ports)
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

## Scout — concrete anchors (2026-07-21 sizing session)

Read-only scout of the tree, so the implementer starts from a map, not a blank grep.
Confirms the design above and pins the exact edit sites.

- **SysV arg regs (the thing to fork for MS x64):** `compiler/ir_codegen.inc:4163-4170`
  assigns int args 0→rdi,1→rsi,2→rdx,3→rcx,4→r8,5→r9; float args → xmm0..7 at
  `:4051-4056` / `~4151-4160`. The C-call ABI branch is `ir_codegen.inc:4029-4036`
  (`if ProcExternal or ProcCdecl`). **There is no callconv enum** — convention is a
  per-proc boolean (`ProcCdecl[]`, `symtab.inc:4764`), hardwired to SysV. MS x64 =
  a new discriminator threaded through IR_CALL lowering + the prologue param-spill
  (`parser.inc:24317`). Fork rcx/rdx/r8/r9, add the 32-byte shadow-space reservation,
  swap the callee-saved set (Win64: RSI/RDI + XMM6-15 callee-saved; SysV: scratch).
- **The external-call path already treats calls as opaque clobber barriers**, so the
  optimizer needs no new teaching — MS x64 fills the arg-mapping into machinery that
  exists. This is why piece is **moderate, not large** (linear codegen fork, not new
  subsystem). The two genuine debug traps: missing shadow space → silent stack
  corruption; forgotten XMM6-15 save → silent FP corruption across a callback.
- **PE writer:** ELF-only today in `compiler/elfwriter.inc` (3303 LOC): `writeELF`
  `:1488`, ehdr/PT_LOAD/reloc helpers `:433-702`. New `pewriter.inc` reuses the
  `writeU8/16/32/64` + fixup byte-writers (`:555-702`); only the container (DOS stub,
  PE\0\0, COFF hdr, optional hdr, `.idata` IAT/ILT) is new. Linear to write — the pain
  is first-boot: the Windows loader rejects a malformed PE **silently/cryptically**
  ("not a valid Win32 app"), so budget debug time for RVA math + IAT twin-array
  (INT/IAT) + section file-vs-virtual alignment. Output dispatch to patch:
  `compiler.pas:948-961` (currently arch-keyed only).
- **Platform axis is half-built (good news — the enum already exists):** `defs.inc:636`
  has `TargetPlatform` = { PLATFORM_POSIX=0, PLATFORM_ESP=1 }; globals at
  `defs.inc:925/:1584`, derivation `compiler.pas:612-623`. Add `PLATFORM_WINDOWS`,
  a `--target=x86_64-windows` CLI surface (`compiler.pas:276-339`), guard it to
  `TARGET_X86_64`, and wire it into the emitter (`compiler.pas:948`) + RTL-PAL
  selection (`compiler.pas:678-683`). This sub-piece is **trivial** — the `(arch,os)`
  product is already in the type system, just missing the Windows member.

## Refined scope (2026-07-21) — cross-compile only, single-thread first

- **Cross-compile FROM Linux only.** Self-hosting *on* Windows is explicitly **not a
  goal** — not now, maybe once all features land as a distant 2nd. The target exists to
  emit Windows apps transparently, nothing more. The ELF default and self-host gate stay
  bit-identical; Windows is purely additive output.
- **Single-threaded console first; defer threads/sync/mmap.** The raw-syscall RTL modules
  that bypass the IO chokepoint — `lib/rtl/palthread.pas`, `palsync.pas`, and the
  `mmap`/`futex`/`clone` sites — are a **threading-model mismatch** (futex ≠ Win event
  objects; `CreateThread`/`WaitForSingleObject`/`VirtualAlloc`). Not covered by the
  ~10-symbol kernel32 binding above and NOT required for a console or a simple GUI app.
  Land Windows single-threaded; file threads as a follow-up only when an app needs them.
- **GUI is a separate, best-effort, un-gated follow-up** — see
  [[feature-pcl-win32-widgetset]] under the GUI umbrella
  [[feature-pcl-cross-platform-gui]]. Native user32/gdi32, zero-dep (no GTK bundle).
  Correctness/layout/signal parity **explicitly not guaranteed or gated** (no Windows
  box; Wine-smoke only). Console + stdio is the spine that earns "runs on Windows"; GUI
  bolts on after.

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

## Log

### 2026-11-14: phase 1, a console .exe that runs under Wine

Spelled `--os=windows`, not `--platform=windows`: it is a kernel like
`--os=freebsd`, and the platform axis stays POSIX. The design is the BSD
ports' design, not the one above. **The full MS x64 codegen fork in the
scout section turned out to be unnecessary:**

- **Translator.** `compiler/builtin/winabi.pas` (KernelTranslated, so the
  shared syscall thunk calls PXXWinSyscall). kernel32 only, no CRT. Covers
  read/write/close/fstat on the std handles, writev, mmap (anonymous),
  munmap, mprotect, brk (a reserved 1 GiB region committed on demand),
  clock_gettime (precise FILETIME / unbiased interrupt time), nanosleep,
  getpid/gettid, uname, getrlimit, exit, and no-ops for the signal, futex and
  arch_prctl calls the startup makes. Anything else is -ENOSYS, named on
  stderr under PXX_WINABI_TRACE=1. Constant divisors only: the translator
  units have no divide-by-zero stub.
- **Calling convention: an adapter at the call site, not a codegen fork.**
  EmitExternalIndirectCall, under KERNEL_WINDOWS: `sub rsp,48`, args 5/6 to
  [rsp+32]/[rsp+40], rdi/rsi/rdx/rcx -> rcx/rdx/r8/r9, call, `add rsp,48`.
  SysV-stacked args 7+ land at [rsp+48], exactly Microsoft's slot, so any
  arg count works. The callee-saved difference is harmless in this
  direction (MS preserves a superset). Not done: float args (MS assigns
  xmm0-3 by position), and calls FROM Windows into pxx code (thread start,
  exception handler, window procedures). Those need the reverse adapter.
- **PE writer.** `compiler/pewriter.inc`. FileAlignment = SectionAlignment
  = 4096 makes file offset = RVA, so the ELF layout carries over: code at
  RVA $1000 (codeOffset), data after the page-padded code, and the same
  ApplyImageFixups. The x86-64 GOT slots become the IAT (PreparePEImports
  appends IAT, ILT, descriptors, hint/name entries and DLL names to Data[]).
  Fixed base $400000 with RELOCS_STRIPPED, so there is no .reloc and no ASLR.
  Stack commit = reserve = 8 MiB, because pxx frames do not probe the guard
  page.
- **TLS.** gs is the TEB, so every `gs:[disp]` (four hand-encoded sites, all
  the asmtext ones) is emitted unprefixed as a rip-relative reference to
  BSS_TLS_MAIN + disp (EmitTlsSegPrefix/EmitTlsSegDisp, TlsSegAbsolute). One
  thread only, so `--threadsafe` is refused.
- **Entry.** Windows calls the entry point like a function, with no argc
  block. The stub makes the WIN_PXX_ARGBLOCK pseudo-call. winabi builds the
  Linux argc/argv/envp/auxv image from GetCommandLineW (msvcrt's quoting
  rules) and GetEnvironmentStringsW, converted to UTF-8, and the stub copies
  it onto an aligned stack.

Verified:

- `make test-windows` (new; tools/vm/wine.sh, prefix /data/vm/wine on
  plexus): 22 Pascal/C/NilPy programs, plus the {$Q+} trap program at 0-5
  arguments, against the Linux build of the same source.
- Survey: 63/69 random Pascal tests, and 34/36 C and NilPy ones, already
  matched. The failures were a libc.so.6 external, an sqlite one, a float
  extern, pselect6 and files.
- Byte identity: 449 builds (Linux default, --threadsafe, -O2, the four
  BSDs, aarch64, Minix, --rtl-libc) are identical to HEAD.

Next, in order:

- **Phase 2:** files (openat/CreateFileW, which also exercises the 7-arg
  call), stat, getdents64, /proc/self/environ and /proc/self/exe, cwd,
  pselect6/poll on the std handles, processes (CreateProcess). Then the
  survey list grows.
- **Phase 3:** a vectored exception handler for hardware faults (the
  reverse adapter), threads through the PE TLS directory (`mov rax,
  gs:[0x58]; mov rax,[rax]`, since the exe's TLS index is 0) and
  CreateThread, and sockets (ws2_32).
- **Later:** .reloc + ASLR, float args in the adapter, and arm64.

### 2026-11-14: phase 2a, files and directories

winabi's fd table holds three kinds of fd: a HANDLE, an in-memory file
(/proc/self/environ, served from the envp strings WinArgBlock already
built), and a directory (its UTF-16 path plus a FindFirstFileW enumeration,
one page each). The calls added:

- open/openat through CreateFileW. This is the 7-argument call, so the
  adapter's stacked-argument path is now exercised.
- read/write with O_APPEND, lseek, pread/pwrite (OVERLAPPED) and the vector
  forms, the stat family (GetFileAttributesExW and
  GetFileInformationByHandle into the Linux struct stat), getdents64, mkdir,
  unlink and rmdir (and the *at forms with AT_REMOVEDIR), rename (also
  renameat/renameat2), access, getcwd/chdir/fchdir, ftruncate,
  fsync/fdatasync, dup/dup2/dup3/F_DUPFD, pipe/pipe2, fcntl, readlink
  /proc/self/exe, and sysinfo.
- The chmod/chown/umask/utime family answers 0.
- GetLastError maps to errno (WinErr).

Survey: 56/60 file-flavoured tests matched before preadv/pwritev and
sysinfo were added, and both of those now pass. The remaining misses are
a libc.so.6 printf and a socket. test-windows gained 13 file programs and
test_os_env (environment + argv, argv0 filtered).

Next: select/poll, then processes. The runtime forks and execs; Windows
cannot fork, so that needs a CreateProcess path in lib/rtl/subprocess.pas
and the crtl, not just the translator.
