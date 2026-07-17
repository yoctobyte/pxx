# Additional OS targets (BSD / macOS via syscall mapping; Windows deprioritized)

- **Type:** feature
- **Status:** rainy-day 
- **Owner:** —
- **Opened:** 2026-06-16

## Premise

PXX emits **static, syscall-only** binaries (no libc, no `ld.so`, no shared libs;
`ldd` → "not a dynamic executable"). The only host contract is the kernel syscall
ABI. So porting to another Unix-like OS is mostly **mapping out its syscall
numbers + ABI**, not a userland/libc port.

## Scope

- **BSD (Free/Open/Net):** already understood to be "a matter of mapping
  syscalls" — different numbers, same static-binary model. Bounded.
- **macOS:** expected to be the same shape — map the Mach/BSD syscall layer + the
  Mach-O object format (PXX currently emits ELF; macOS needs Mach-O, so a second
  object writer alongside `elfwriter.inc`). The codegen/backends are unchanged;
  it's an OS-ABI + container-format port.
- **Windows:** **explicitly deprioritized.** Different model (PE + Win32/NT
  syscalls are not a stable public contract), and out of the project's interest.
  Community contribution welcome; not on the roadmap.

## Notes

- **NOT only syscall numbers — a few Linux `/proc`-based readbacks need OS
  equivalents too.** The static-binary model maps cleanly, but some runtime code
  reads Linux `procfs` text, which BSD/macOS do not have:
  - **CPU load sampler** (`lib/rtl/palparallel.pas`, `PXXQueryFreeCores` for the
    parallel-for `pwLoadOnce`/`pwLoadCont` policies) reads `/proc/stat`. BSD →
    `sysctl kern.cp_time` (per-CPU jiffies); macOS → `host_processor_info` /
    `sysctlbyname`. No `/proc/stat` there. It already fails SAFE (falls back to
    the fixed worker count), so this is a *feature-parity* item, not a blocker.
  - **CPU count** uses `sched_getaffinity` (`palparallel`); BSD/macOS →
    `sysctl hw.ncpu` / `hw.activecpu`.
  - Audit for any other `/proc/*` or Linux-specific `sysfs` reads when porting
    (grep `'/proc/'` across `lib/rtl/**`). Treat the sampler/affinity as part of
    the per-OS port, alongside the syscall table.

- This is about the **compiler binary's** host portability and what users can
  target. The static-syscall-only design is what makes it cheap (see the
  kernel-only portability property).
- Per-OS work = syscall table + entry/exit ABI + object/container writer
  (ELF done; Mach-O / PE per target). Backends (x86-64/aarch64/arm32/...) are
  reused as-is.
- Distro packaging stays trivial: source + a static binary + a man page.
