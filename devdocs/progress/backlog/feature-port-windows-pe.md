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
