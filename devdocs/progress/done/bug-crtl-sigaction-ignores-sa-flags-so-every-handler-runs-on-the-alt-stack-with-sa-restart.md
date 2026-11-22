---
slug: bug-crtl-sigaction-ignores-sa-flags-so-every-handler-runs-on-the-alt-stack-with-sa-restart
track: crtl
prio: 45
type: bug
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (building micropython v1.24.1's unix port with pxx)
tags: [crtl, signals, rtl, gc]
blocked-by: []
summary: "crtl's sigaction passes only the handler and SA_SIGINFO to __pxx_c_sigaction. The signal runtime installs every handler with SA_RESTORER|SA_RESTART|SA_SIGINFO|SA_ONSTACK (x86-64: ir_codegen.inc, `mov edx, 0x1C000004`), so every C handler runs on pxx's BSS alt stack and every interrupted syscall restarts, whatever sa_flags asked for. glibc applies the caller's flags. micropython's thread GC signals each thread; its handler scans from its own sp to the thread's stack top, and from the alt stack that range crosses unmapped memory and crashes (select_poll_eintr). Boehm GC's stop-the-world uses the same pattern."
---

# crtl's sigaction ignores sa_flags

## What happens

- `lib/crtl/src/signal.c` `sigaction()` drops `act->sa_flags` except
  SA_SIGINFO. `oact->sa_flags` reports only SA_SIGINFO too.
- The shared install sequence (SigInstallAddr in EmitSignalRuntime, and its
  counterparts on the other five targets) always sets SA_ONSTACK and
  SA_RESTART. That suits Pascal: a stack-overflow SIGSEGV needs the alt stack,
  see done/bug-a-a-cloned-thread-has-no-sigaltstack-so-its-stack-overflow-is-unhandleable.
  But C code that did not ask for those flags gets them anyway.

## Seen in

micropython tests/extmod/select_poll_eintr.py. A second thread calls
gc.collect(). mp_thread_gc_others does pthread_kill(SIGUSR1) to the main thread,
which is inside poll(). The handler, gc_helper_collect_regs_and_stack, scans
`[sp, stack_top)`. With rsp on the BSS alt stack (0x1472940 in the crashing
run), that range runs up through unmapped memory, and the process gets SIGSEGV
in the GC. gcc+glibc: handler on the thread's own stack, poll returns EINTR
and is retried, test passes.

## Fix shape

Carry the caller's SA_ONSTACK and SA_RESTART (and SA_NODEFER, SA_RESETHAND, if
wanted) from C's sigaction through __pxx_c_sigaction into the install, per
signal. The Pascal SetSignalHandler path keeps today's flags. This touches all six
targets' install sequences. Before changing it, check which of them also
force SA_RESTART.

Test against gcc: a handler that records its own `&local` and compares it with
main's stack range; a read() on a pipe interrupted by a handler installed
without SA_RESTART should give EINTR.

## Done (2026-11-22)

Not by changing the six install sequences: those stay as they are, and Pascal's
SetSignalHandler keeps ONSTACK|RESTART. Instead:

- New PAL entry PalSetSignalFlags(sig, on, off) (posix backend). It reads
  the installed disposition back with rt_sigaction, changes the flags word,
  and writes it back. The flags word is the second native word of the
  kernel's struct sigaction on every Linux arch: x86-64, i386, arm32,
  aarch64 and riscv32 were measured. On the BSDs, Minix and Windows it does
  nothing (the runtime's flags stay). On ESP it returns 0, on WASI
  unsupported.
- pxxcio bridges it as __pxx_c_sigflags. crtl's sigaction calls it after
  __pxx_c_sigaction for a real handler: SA_ONSTACK, SA_RESTART and
  SA_NODEFER become exactly what the caller asked for. signal() is glibc's
  BSD signal: SA_RESTART, no alt stack. oact->sa_flags reports the
  caller's flags.
- SA_RESETHAND and SA_NOCLDSTOP are accepted and not acted on, as before.
  sigaltstack is still a no-op, so a handler that asks for SA_ONSTACK runs
  on pxx's alt stack, not on one the program supplied.

Test c_sigaction_flags, against gcc+glibc, on x86-64, aarch64, i386 and
riscv32 (arm32 also measured the same): the handler runs on the thread's
own stack; a read interrupted without SA_RESTART gives EINTR (with the old
crtl it restarted forever, so the row has a timeout); with SA_RESTART and
under signal() it restarts and returns the byte the handler wrote;
SA_NODEFER nests, and without it the signal is deferred; oact reports the
flags.

micropython, all 216 units built by pxx (nlrx64.c with -U__GNUC__ -D__GNUC__=8),
no MICROPY_NLR_SETJMP: select_poll_eintr passes; 898 of 908, and the 10
failures are ones gcc's build also has.
