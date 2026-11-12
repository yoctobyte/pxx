---
title: FreeBSD and the BSDs
order: 62
---

# FreeBSD and the BSDs

PXX writes native **FreeBSD/amd64** executables from Pascal, C and Nil
Python. The other BSDs are not supported yet; [their plan](#openbsd-netbsd-and-minix)
is at the end of this page.

```sh
./pxx --os=freebsd hello.pas hello      # copy hello to the FreeBSD box and run it
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

## Not supported

The compiler refuses these with a message that names the reason:

- CPUs other than x86-64 (`--target=aarch64` and so on)
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

These are not supported yet, and `--os=openbsd` is an unknown option.

OpenBSD only lets a program make a system call from an address it has
declared in advance (pinsyscalls). The base system's static binaries do this
with a table in the executable. A test on 2026-11-12 showed that a hand-patched
pxx hello-world with such a table runs on OpenBSD 8.0 without libc. So OpenBSD
could work like FreeBSD, with its own translator, and would not need to go
through libc. The cost is that OpenBSD's system call numbers can change between
releases, so each binary would be tied to one release. Which way to go has not
been decided.

`--rtl-libc` alone is not enough on any of them: it passes Linux system call
numbers to libc's `syscall()`, which OpenBSD's libc does not even export.
NetBSD and Minix have stable system call numbers.

The measurements and the plan are in
`devdocs/progress/working/feature-port-libc-family-openbsd-netbsd-minix.md`.

DragonFly BSD is close to FreeBSD and should be nearly free, but nobody has
tried it.

## Next

- [Targets](./index.md)
- [Command-line reference](../reference/cli.md)
