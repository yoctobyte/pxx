---
title: FreeBSD and the BSDs
order: 62
---

# FreeBSD and the BSDs

PXX writes native **FreeBSD/amd64** and **FreeBSD/arm64** executables from
Pascal, C and Nil Python. OpenBSD, NetBSD and DragonFly BSD are experimental and Minix is not supported yet;
[their notes](#openbsd-netbsd-and-minix) are at the end of this page.

```sh
./pxx --os=freebsd hello.pas hello      # copy hello to the FreeBSD box and run it
./pxx --os=freebsd --target=aarch64 hello.pas hello   # the same for FreeBSD/arm64
```

Measured on FreeBSD 15.1 (November 2026). FreeBSD 14 or newer is needed:
`timerfd` arrived in 14.

## How it works

A FreeBSD build is a Linux build with one extra piece. The program still needs
no libc, and the runtime libraries are the same ones a Linux program uses. The
difference is the kernel entry: every system call goes to a small translator,
`compiler/builtin/fbsdabi.pas`, that is compiled into the program. It
translates in both directions:

- system call numbers
- flag bits and constants (`open` flags, `mmap` flags, socket options, `ioctl`
  requests and so on)
- struct layouts (`stat`, `sockaddr`, `msghdr`, `termios`, `sigaction`,
  `siginfo`, `ucontext` and more)
- signal numbers
- `errno` values

Anything the translator does not recognise returns `ENOSYS`, as an unknown
system call does on Linux.

Some Linux interfaces have no FreeBSD system call of their own. The translator
builds them from FreeBSD parts:

| Linux | Built from, on FreeBSD |
| --- | --- |
| `epoll` | `kqueue` |
| `futex` | `_umtx_op` |
| `clone` (threads) | `thr_new`, in the compiler's clone stub |
| `/dev/ptmx`, `TIOCGPTN` | `posix_openpt`, `FIODGNAME` |
| `fallocate` (mode 0) | `posix_fallocate` |
| `personality` | a value kept in the program |
| `prctl(PR_SET_NAME / PR_GET_NAME)` | `thr_set_name` and a kept copy |
| `/proc/self/environ`, `/proc/self/exe`, `/proc/self/fd/N`, `/proc/sys/kernel/hostname` | the startup block, `sysctl`, `fcntl(F_KINFO)` |

The executable carries the `NT_FREEBSD_ABI_TAG` note every native FreeBSD
program has. Without it, FreeBSD reports a stack overflow as `SIGBUS` instead
of `SIGSEGV`.

## What works

Each item below has been run in a FreeBSD VM and compared with the Linux build
of the same program: the output has to be identical.

- files, directories, `stat`, links, `statfs`
- environment, arguments, the program's own path
- processes: `fork`, `exec`, `wait`, pipes, `subprocess`
- signals, including a crash turned into an exception
- `select`, `poll` and the async scheduler (`epoll` on top of `kqueue`)
- timers (`timerfd`) and `eventfd`
- sockets: IPv4, IPv6 and Unix, including `sendmsg`/`recvmsg` and passing file
  descriptors (`SCM_RIGHTS`)
- terminals (`termios`) and ptys
- threads built with `--threadsafe`: `TThread`, C `pthread_create`, `threadvar`,
  `thread_local`, mutexes, parallel for
- the scheduler calls, `mlock`, `fallocate`, `swapon`/`swapoff`

Every Pascal library test (`test/lib_*.pas`, 157) and C test (`test/c_*.c`,
224) was run on both kernels on 2026-11-12. Every difference that was a
translator bug was fixed. The rest are listed under
[Not supported](#not-supported) or were caused by the test environment.

## FreeBSD/arm64

`--os=freebsd --target=aarch64` uses the same translator. On arm64 the
runtime speaks Linux's generic system call table, so the translator has a
front layer (`compiler/builtin/lxa64front.inc`, shared with NetBSD) that maps those numbers
onto the x86-64 ones the rest of it understands and converts the four things
that differ between Linux's two 64-bit ABIs:

- `struct stat` (128 bytes on arm64; `st_nlink` and `st_mode` differ in size
  and place);
- `struct epoll_event` (16 bytes, not packed);
- `struct sigaction` (no `sa_restorer`, so the mask is at offset 16);
- four `open` flags (`O_DIRECTORY`, `O_NOFOLLOW`, `O_DIRECT`, `O_LARGEFILE`
  have other values).

arm64 has no `fork` call: `clone(SIGCHLD)` becomes FreeBSD's `fork`.

The compiler side: every `svc #0` the aarch64 backend emits becomes a `bl` to
one shared stub that calls the translator, so no hand-written branch distance
moves. FreeBSD/arm64 starts a program with the argument block in `x0` and `sp`
rounded down to 16 bytes; the first instructions slide `argc`, `argv`, `envp`
and the auxiliary vector down so that `sp` points at `argc`, as on Linux.
Threads start with `thr_new`, which is handed the new thread's TLS block as
its `tls_base` (FreeBSD does not copy `tpidr_el0` to a new thread). Signal
handlers get a Linux arm64 `ucontext`, so `__pxxSigPCPtr` works.

`make test-freebsd-arm64` runs about 70 programs on an arm64 VM and compares
them with the Linux aarch64 build run under `qemu-aarch64`: files, signals,
threads, sockets, async I/O, timers, termios on a pty, ptys, `-g`, and the C
and NilPy runtimes. It passes. The VM runs under TCG emulation, so it is slow:
`PXX_FBSD_ARCH=aarch64 tools/vm/freebsd.sh start`, port 2228, image under
`/data/vm/freebsd-arm64`. Its first boot installs base-system updates and
takes about 20 minutes.

## Not supported

The compiler refuses these with a message that names the reason:

- CPUs other than x86-64 and aarch64 (`--target=arm32` and so on)
- `--shared` and `.so` output
- `--emit-obj` and `.o` output
- `--rtl-libc`

These compile, but the call fails when the program runs:

- **Threads through glibc's `pthread_create`**, the route a program takes when
  it links the system C library. Use `--threadsafe` threads.
- **Linux-only `/proc` files.** Only the four listed in the table above exist;
  `/proc/self/maps`, `/proc/self/stat` and the rest do not.
- **Linux-only interfaces:** `SCM_CREDENTIALS`, abstract Unix sockets,
  `inotify`, extended attributes (`xattr`), SysV IPC, `klogctl`, `adjtimex`,
  Linux-specific device `ioctl`s.
- **`acct`** is left unmapped on purpose. Tests in the VM run as root, and a
  working `acct` call there would switch on process accounting.
- **A raw `syscall` instruction in inline assembly** goes straight to the
  FreeBSD kernel and never reaches the translator, so it is read with FreeBSD's
  numbers. For example, 39 is `getpid` on Linux and `getppid` on FreeBSD. Call
  the C library function instead.

Device numbers are real FreeBSD numbers: `/dev/null` is 0:20, not Linux's 1:3.

## Testing it

`tools/vm/freebsd.sh` runs a FreeBSD 15.1 VM under QEMU (KVM). The image is
several gigabytes. It goes in `$PXX_VM_DIR/freebsd`, which defaults to
`/data/vm/freebsd`; keep it off a small root filesystem.

```sh
tools/vm/freebsd.sh fetch            # one time: download, verify, set up the ssh key
tools/vm/freebsd.sh start            # boot headless; ssh on 127.0.0.1:2223
tools/vm/freebsd.sh run ./hello      # copy in, run, relay stdout/stderr/exit code
tools/vm/freebsd.sh stop
```

`run` uses an 8 MB stack limit, as Linux does by default, and passes on any
`PXX_TEST_*` environment variables. `PXX_VM_PTY=1` runs the program on a
terminal under `script(1)`, for tests that need one.

`make test-freebsd` builds each listed test for both kernels, runs one copy
on the host and the other in the VM, and requires identical output. The
repository's hooks treat it as a full suite, so run it as
`PXX_ALLOW_FULL_SUITE=1 make test-freebsd`.

### Things the VM does differently

These showed up as differences in the 2026-11-12 run and are not translator
bugs:

- tests run as root, so permission checks (a mode-000 file, for example)
  pass where they fail for a normal user
- there is no `/etc/localtime`
- `/bin/sh` words its error messages differently
- `argv[0]` is `/tmp/pxxbin`
- free ports are assigned randomly
- stdout and stderr travel over ssh separately, so their order can differ

## Changing the translator

Before you add to `fbsdabi.pas`:

- **Take every number from the FreeBSD headers in the VM** (`/usr/include/sys/`),
  not from memory or a web page. Take the Linux side from the host's headers.
- **Check the Linux build stays byte-identical.** The translator is only
  compiled into `--os=freebsd` programs. A change to shared compiler code can
  still change Linux output, so compare a Linux build with the previous
  compiler.
- **Mind the order of checks.** Linux and FreeBSD can give different errors
  for the same bad call. For example, `socket()` with a bad type is `EINVAL` on
  Linux before the family is looked at. Copy Linux's order.
- **Some FreeBSD calls return the error as a value.** `posix_fallocate`, for
  example, does not set the carry flag.
- **The clone stub is compiler code.** `compiler/thread_emit.inc` has a
  `thr_new` path under `--os=freebsd`. Thread exit, `CLONE_CHILD_CLEARTID` and
  the TID handshake are documented there.
- **The ELF header layout is shared.** The FreeBSD note sits in the slot between
  the program headers and the code, and the note must end where code starts.
  `--ldso-runnable` (and `--gibix`) puts a 144-byte minimal dynamic block in
  the same slot, before the note. The layout is: headers, ldso block, FreeBSD
  note, code. Read the comment at the note in `elfwriter.inc` (both executable
  writers) before changing either.

The work log, with the reasons behind each choice, is in
`devdocs/progress/working/feature-port-freebsd-native.md`.

## OpenBSD, NetBSD and Minix

Minix is not supported yet. OpenBSD, NetBSD and DragonFly have EXPERIMENTAL
`--os=openbsd`, `--os=netbsd` (since 2026-11-12; both also on arm64) and
`--os=dragonfly` (since 2026-11-13, x86-64 only). The OpenBSD one may
still be withdrawn in favour of going through libc; the choice has not been
made.

### `--os=openbsd` (experimental)

OpenBSD only lets a program make a system call from an address it has
declared in advance (pinsyscalls). The base system's static binaries do this
with a table in the executable, and that is what pxx writes. The design is the
FreeBSD one: the program is built against Linux, and
`compiler/builtin/obsdabi.pas` translates every system call at run time.

What is different from FreeBSD:

- **The pin table.** A `PT_OPENBSD_SYSCALLS` program header (in the slot
  `PT_GNU_STACK` uses on Linux) points to a table after the data. The table
  pins every system call number, 1 to 330, to the single `syscall`
  instruction in `ObRawA`. A raw `syscall` anywhere else in the program is
  killed with SIGABRT, and ktrace shows a `PINS` line. The kernel ignores the
  whole table if any entry is out of range, and it reads the table only when
  the program has no `PT_INTERP`.
- **No branch-target CFI.** On a CPU with IBT (amd64) or BTI (arm64),
  OpenBSD faults an indirect branch that does not land on an `endbr64` or
  `bti` instruction, and pxx emits neither. The executable carries a
  `PT_OPENBSD_NOBTCFI` program header, the kernel's opt-out, as ports
  built without landing pads do. The VMs have neither feature (the build
  host has no IBT, and OpenBSD/arm64 does not boot on qemu's BTI-capable CPU
  models), so this part is read from the kernel source, not measured.
- **The ident note.** The note is named "OpenBSD", type 1, description 0. It
  sits where the FreeBSD note goes. Without it OpenBSD answers ENOEXEC.
- **TLS uses fs.** OpenBSD userland cannot set the GS base; `__set_tcb` sets
  FS. Under `--os=openbsd` the compiler writes pxx's TLS accesses with the
  fs prefix instead of gs (`TlsSegPrefix` in `compiler/defs.inc`), and the
  translator turns `arch_prctl(ARCH_SET_GS)` into `__set_tcb`.
- **No brk.** OpenBSD has no brk call, so the translator emulates it with a
  1 GiB `PROT_NONE` reservation that it opens up with `mprotect`.
- **`/proc` files.** `/proc/self/environ` is built from
  `sysctl kern.proc.args.<pid>.env`. It is served through a pipe if it fits
  in 16 KiB, or through an unlinked file in `/tmp` if not (OpenBSD has no
  anonymous shared memory). `/proc/self/exe` is `argv[0]` made absolute. That
  is right when the program was started by a path, and it gives ENOENT when the
  program was found through a `PATH` search.
- **Release-bound.** OpenBSD's system call numbers are not a stable ABI. The
  numbers in `obsdabi.pas` are 8.0's, measured from its `/usr/include`, and a
  binary is tied to that release.

Tested on 2026-11-12 on OpenBSD 8.0 amd64: hello world, and text-file
reading and writing, `FindFirst`, directory creation and removal, the
environment, the current directory, `ParamStr(0)` and the clock. The output
was identical to Linux.

Signals work the FreeBSD way: the translator installs its own entry point,
which hands the program's handler a Linux-shaped siginfo and ucontext and
copies the registers back. Three OpenBSD details matter:

- The signal mask is a single 32-bit word, passed by value.
- OpenBSD kills a process that makes a system call while its stack pointer
  is outside a `MAP_STACK` mapping. pxx's alternate signal stack is 32 KiB of
  BSS, but `sigaltstack` converts the region it is given, so the program's
  buffer is registered unchanged. This was measured, not taken from the
  documentation.
- OpenBSD 8.0 reports every SSE floating-point trap as `FPE_FLTINV` and
  leaves the trap number 0. The translator works out the real cause from the
  saved MXCSR, the way Linux does.

`test_signal_num`, `test_signal_sp_rewrite`, `test_stack_overflow_raise`,
`test_signal_bss_alias`, `test_signal_handler_callback_b336`,
`test_float_exception_mask` and an `--fpc-mem-errors` nil write give the same
output on OpenBSD as on Linux (2026-11-12).

Threads work too (`--threadsafe`):

- **Thread creation.** The clone stub's OpenBSD leg calls `clone` through
  the translator, which turns it into `__tfork`. That system call has its own
  pinned site, in `ObTforkA`, because the child resumes after the instruction
  on its new stack and cannot return through the translator. `ObTforkA` sends
  the child to the stub's child entry.
- **Thread exit.** Linux's kernel clears the tid word and wakes the joiner
  (`CLONE_CHILD_CLEARTID`); OpenBSD's does not. An exiting thread therefore
  takes a lock and moves to a shared exit stack. There it clears the word and
  wakes both futex queues, then calls `__threxit` with the lock word as its
  argument, so the kernel releases the lock once the thread is gone.
- **Thread stacks** must be `MAP_STACK`. Under `--os=openbsd` the compiler
  defines `PXX_OS_OPENBSD`, and `palthread` and `scheduler` (coroutines) then
  map their stacks with Linux's `MAP_STACK` bit, which the translator passes
  on. A program that maps its own stack for a raw `__pxxclone` call (as
  `test_thread_clone` does) must set that bit itself, or the thread is killed
  at its first system call.
- **futex.** WAIT, WAKE and REQUEUE are translated, and the BITSET forms
  are accepted with a full mask.

`test_a_threadvar_is_per_thread`, `test_cross_futex_through_the_pal`,
`lib_fpc_thread_surface` (40 runs in a row), `lib_classes_tthread`,
`test_signal_threads`, `test_signal_num_threads_race` and the C tests
`c_pthread_join_returns_value`, `c_errno_is_per_thread`,
`c_thread_local_is_per_thread`, `c_pthread_detach` and
`crtl_pthread_recursive_mutex` give the same output on OpenBSD as on Linux.

Sockets, `ppoll`/`pselect6` and epoll work too.

- **Sockets** use FreeBSD's translation (the structs are the same) with
  OpenBSD's numbers. `AF_INET6` is 24, `SOCK_NONBLOCK`/`SOCK_CLOEXEC` are
  `0x4000`/`0x8000`, and `MSG_NOSIGNAL` is `0x400`. `SO_PEERCRED` is
  reordered into Linux's pid, uid, gid.
- **epoll** runs over kqueue, as on FreeBSD. OpenBSD's `struct kevent` is
  32 bytes, not 64.
- **IPv6 is always v6-only** on OpenBSD: a `[::]` listener never accepts
  IPv4. So `lib_net_v6only`'s two dual-stack checks fail there, and that is
  the system's behaviour, not a bug in the translation.

`csocket_loopback_b88`, `c_crtl_sock_flags`, `c_crtl_cmsg_and_socket_levels`,
`c_crtl_inet6`, `lib_net`, `lib_net6`, `lib_net_timeout`, `lib_dns_tcp` and
`lib_asyncnet6` (coroutines over epoll) give the same output on OpenBSD as on
Linux.

termios and the tty ioctls use FreeBSD's tables, with OpenBSD's few
differences: there is no `IUTF8`, `OCRNL`/`ONOCR`/`ONLRET` are
`0x10`/`0x40`/`0x80`, and `CRTSCTS` is `0x10000`. `c_os_freebsd_termios` gives
the same output as on Linux when run on a real terminal. Under OpenBSD's
`script(1)` with stdin redirected from `/dev/null`, the pty starts with every
flag at 0, because `script` copies the settings of a terminal it does not
have.

Some things OpenBSD lacks are emulated:

- **timerfd** is a kqueue holding one `EVFILT_TIMER`. A kqueue fd is
  readable while it has a pending event, so epoll and poll see it fire; a
  `read` answers the expiration count. pxx's scheduler parks every timed
  wait on a timerfd (`CoSleep`, the `*Timeout` waits, async DNS). Not
  emulated: a repeat interval different from the first expiry, and the
  values `timerfd_gettime` reports.
- **`/dev/full`** is `/dev/zero` with writes failing ENOSPC.
- **`/proc/sys/kernel/hostname`** is served from `kern.hostname`.
- **`readlink("/proc/self/fd/N")`** works for a directory: the translator
  changes into it, reads the cwd and changes back. crtl's `fchdir` relies on
  this. For any other fd the answer is ENOENT.
- **Pseudo-terminals.** Opening `/dev/ptmx` opens `/dev/ptm` and asks it
  for a pair with `PTMGET`. The master is kept and the slave is closed.
  `TIOCGPTN` answers the master's minor number N, and opening `/dev/pts/N`
  opens OpenBSD's slave of that number, `/dev/tty` + `pqrstuvwxyzPQRST`[N div
  62] + `0-9a-zA-Z`[N mod 62] (so `/dev/pts/0` is `/dev/ttyp0`). A stock
  `/dev` only has the 62 `p` ptys, so a 63rd pair fails with ENOENT.
  `unlockpt` succeeds, because OpenBSD ptys have no lock.
- **`fallocate`** mode 0 grows a short file with `ftruncate`. OpenBSD cannot
  preallocate.
- **Scheduling.** OpenBSD has no POSIX scheduling policies, so the
  `sched_*` calls answer as Linux does for a `SCHED_OTHER` process.
  `sched_getaffinity` reports every online CPU.

`make test-openbsd` runs about 90 programs on the VM and compares their
output and exit code with the Linux build. It covers files, signals, threads,
sockets, async I/O, timers, termios (on a pty), ptys, and the C and NilPy runtimes.

Not done yet:

- `/proc/self/maps` and the rest of `/proc`, apart from the files above.
- eventfd.
- A thread stack mapped by the program itself for a raw `__pxxclone` call
  must have `MAP_STACK`.

Anything that is not mapped answers ENOSYS.

To try it, run `tools/vm/openbsd.sh start`, then
`tools/vm/openbsd.sh run <binary>`. Set `PXX_VM_PTY=1` to run the binary on a
real terminal. `PXX_TEST_*` environment variables are passed through.

**OpenBSD/arm64.** `--os=openbsd --target=aarch64` (since 2026-11-13) uses the
arm64 front layer (`compiler/builtin/lxa64front.inc`) that FreeBSD and NetBSD
use, so `obsdabi.pas` keeps one translator for both CPUs. What is arm64's own:

- the system call: number in x8, arguments in x0..x7, carry set on error.
  The kernel resumes 8 bytes past the `svc` (libc's `dsb nsh; isb` barrier),
  so the same two instructions follow every `svc` in the translator. The pin
  table names the `svc` itself.
- the signal frame is a `struct sigcontext` (x0..x29, lr, sp, elr, spsr; no
  FP registers), converted to Linux's arm64 ucontext and back.
- the kernel does not save `tpidr_el0` when it switches threads; it reloads
  it from the value given to `__set_tcb`. The translator hands it the main
  thread's TLS block on the first system call; `__tfork` gives each thread
  its own.
- text is mapped readable, as the program header asks, so the backend's
  literal pools in the code segment work. BTI is switched off by the
  `PT_OPENBSD_NOBTCFI` header (see above).

`make test-openbsd-arm64` runs about 85 programs on an arm64 VM (port 2231,
the stock `miniroot80.img` installed unattended into
`/data/vm/openbsd-arm64`, emulated with TCG; `PXX_OBSD_ARCH=aarch64` selects it
in `tools/vm/openbsd.sh`) against the Linux aarch64 build under `qemu-aarch64`.
It passes.

### `--os=netbsd` (experimental)

The FreeBSD design again: the program is built against Linux, and
`compiler/builtin/nbsdabi.pas` translates every system call to NetBSD 11.1.
The executable carries a NetBSD ident note. NetBSD is the closest of the BSDs
to Linux: it has native `timerfd`, `eventfd`, `futex`, `epoll`, `memfd_create`
and dual-stack IPv6, and its wait statuses, `UTIME_*`, `getrandom` flags and
scheduling policies have Linux's values.

What the translator still has to do:

- **System call numbers.** Many calls have versioned names (`__fstat50`,
  `__getdents30`, `__socket30`, `__sigaction_sigtramp`). The plain numbers are
  the old ABIs.
- **`PAD` arguments.** `mmap`, `lseek`, `pread`, `pwrite`, `preadv`,
  `pwritev`, `truncate`, `ftruncate`, `posix_fallocate` and `mknodat` take a
  padding argument before their 64-bit one. `mmap`'s offset is then the
  seventh argument, which NetBSD reads from the user stack, so the kernel
  entry always pushes a seventh word.
- **`epoll_event`** is 16 bytes in NetBSD's kernel (data at offset 8), not
  Linux's packed 12, so `epoll_ctl` and `epoll_wait` repack it. NetBSD ships
  no `<sys/epoll.h>`; the layout and `EPOLL_CLOEXEC` (= `O_CLOEXEC`) were
  measured with the raw system calls.
- **Directory entries** are up to 8 bytes shorter than Linux's, so
  `getdents64` reads into a buffer two thirds the caller's size and widens.
- **TLS lives in fs**, set with `_lwp_setprivate`, because `setcontext`, which
  ends every signal handler, restores the fs base from the saved context. With
  no libc in the program, fs is free.
- **Signals** are installed with `__sigaction_sigtramp`. The translator's
  entry builds the Linux `siginfo`/`ucontext`, calls the program's handler and
  resumes with `setcontext` itself.
- **errno** 1..84 are FreeBSD's; 85..98 differ. Linux's SIGPWR is NetBSD's
  32, and the real-time signals are shifted by one (NetBSD has 33..63).
- **Threads.** The clone stub calls `clone` through the translator, which
  starts an LWP with `_lwp_create` from a ucontext made by `getcontext`: `rip`
  is the stub's child entry, `rsp` the new stack, and `_UC_TLSBASE` sets the
  thread's fs base. LWPs are created detached; the tid word is cleared and
  its waiters woken by the exiting thread itself, with its signals blocked and
  without touching its stack.
- `/proc/self/environ`, `/proc/self/exe` and `/proc/sys/kernel/hostname` come
  from sysctl, served through a memfd; `readlink("/proc/self/fd/N")` uses
  `fcntl(F_GETPATH)`.
- ptys are NetBSD's own `/dev/ptmx` and `/dev/pts/N`; `TIOCGPTN` reads the
  number from `TIOCPTSNAME`, and `unlockpt` does `TIOCGRANTPT`.

`make test-netbsd` runs about 90 programs on the VM and compares their output
and exit code with the Linux build: files, signals, threads, sockets (IPv4,
IPv6, dual-stack), async I/O, timers, termios on a pty, ptys, `-g`, and the C
and NilPy runtimes. It passes.

Not done yet: `/proc` apart from the files above.

The VM is the stock `NetBSD-11.1-amd64-live.img`, booted under OVMF with
`consdev=com0` in `/EFI/NetBSD/boot.cfg` on its EFI partition, and set up over
the serial console (sshd, dhcpcd, a root key). Run `tools/vm/netbsd.sh start`,
then `tools/vm/netbsd.sh run <binary>`; it listens on port 2227.

**NetBSD/arm64.** `--os=netbsd --target=aarch64` works the same way and shares
FreeBSD/arm64's pieces: the compiler's `svc` thunk and the translator front
in `compiler/builtin/lxa64front.inc`, which maps Linux's arm64 system calls
onto the x86-64 ones `nbsdabi.pas` translates. What is NetBSD's own on arm64:

- the system call number is encoded in `svc`'s immediate; a translator
  computes numbers, so it uses `svc 0` (`SYS_syscall`) with the number in
  `x17`;
- the main thread's thread pointer is written by the program's entry code,
  which the kernel does not see, so the first system call after it reports it
  with `_lwp_setprivate` (otherwise the `setcontext` that ends a signal
  handler would reset it to 0);
- threads are LWPs created from a `ucontext` whose `_REG_TPIDR` is the new
  thread's TLS block;
- the signal frame's registers (`x0`..`x30`, `sp`, `pc`, `spsr`) are in Linux's
  order.

`make test-netbsd-arm64` runs about 75 programs on an arm64 VM (port 2229,
the stock `evbarm-aarch64` `arm64.img` under `/data/vm/netbsd-arm64`, emulated
with TCG) against the Linux aarch64 build under `qemu-aarch64`. It passes.

`--rtl-libc` alone is not enough on any of them: it passes Linux system call
numbers to libc's `syscall()`, which OpenBSD's libc does not even export.
NetBSD and Minix have stable system call numbers.

The measurements and the plan are in
`devdocs/progress/working/feature-port-libc-family-openbsd-netbsd-minix.md`.

### `--os=dragonfly` (experimental)

`compiler/builtin/dfbsdabi.pas` translates every system call to DragonFly BSD
6.4. The executable carries a DragonFly ident note. DragonFly forked from
FreeBSD 4, so the system call numbers, errno 1..92, the signal frame and
`stat` are close to FreeBSD's but not the same. It is x86-64 only: DragonFly
has no other CPU. What is DragonFly's own:

- **Padded calls.** `lseek`, `truncate`, `ftruncate` and `mmap` still take
  the old pad argument before the 64-bit offset; `pread`/`pwrite` and their
  `v` forms go to `extpread`/`extpwrite`. mmap's offset is the seventh
  argument and is read from the user stack.
- **`AT_FDCWD`** is -328243, not -100.
- **Threads** are `lwp_create2`. The kernel gives each new LWP a small id that
  is reused at once, so pxx hands out `lwpid + generation << 16` as the tid
  and keeps the generation in the thread's TLS. Thread exit clears the
  child-tid word, wakes it with `umtx_wakeup` and leaves with `extexit`, on a
  shared exit stack under a spin lock. Futexes are `umtx_sleep` and
  `umtx_wakeup`; `umtx_sleep` has no requeue, so `FUTEX_REQUEUE` wakes all.
- **TLS** is `set_tls_area` on `%gs`, as on Linux.
- **`pipe2`** returns both descriptors in registers.
- **`getdents64`** is `getdirentries`; `/proc/self/exe` and
  `/proc/self/environ` come from sysctl (`kern.proc.pathname`,
  `kern.ps_strings`).
- **Signals.** The ucontext is FreeBSD's shape (mcontext at 64) with
  DragonFly's register order. A SIGFPE's `si_code` is worked out again
  from MXCSR when the kernel leaves it at 0.
- **`dup3`** is `fcntl(F_DUP2FD[_CLOEXEC])`; `fallocate` is `ftruncate`;
  `prctl(PR_SET_NAME)` is `lwp_setname`.
- **IPv6** sockets are always v6-only: `IPV6_V6ONLY` cannot be cleared, so a
  `::` listener does not take IPv4 connections.
- ptys are `/dev/ptmx` and `/dev/pts/N`; the pty number comes from
  `FIODNAME`.

`make test-dragonfly` runs about 90 programs on the VM (the lists of
`make test-netbsd` minus `lib_net_v6only`) and compares their output and
exit code with the Linux build. It passes. The VM is the stock
`dfly-x86_64-6.4.2_REL.img` under `/data/vm/dragonfly`, booted by SeaBIOS
with a serial console and set up from its console (sshd, DHCP, a root key,
root's shell `/bin/sh`, `noatime` off). Run `tools/vm/dragonfly.sh start`,
then `tools/vm/dragonfly.sh run <binary>`; it listens on port 2230.

## Next

- [Targets](./index.md)
- [Command-line reference](../reference/cli.md)
