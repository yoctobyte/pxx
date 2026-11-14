---
title: Windows (experimental)
order: 62
---

# Windows (experimental)

`--os=windows` writes a Windows x64 console executable (PE32+) from Pascal,
C or Nil Python. It is **EXPERIMENTAL**, like every target except Linux.

```sh
./pxx --os=windows hello.pas hello.exe     # run it on Windows, or: wine64 hello.exe
```

The program imports `kernel32.dll` and `ws2_32.dll` (sockets), and only
functions that every Windows since XP and Server 2003 exports, so it needs
no C runtime (msvcrt or ucrt) and no installer. The few newer functions it
uses are looked up when it starts, with a fallback for each one a system
lacks (see below), so the same `.exe` is meant for Windows 8 and later,
Windows 7, and ReactOS.

## Older Windows and ReactOS

| Newer function | Missing on | Stand-in |
|---|---|---|
| `GetSystemTimePreciseAsFileTime` | Windows 7, ReactOS | `GetSystemTimeAsFileTime` (a coarser wall clock) |
| `QueryUnbiasedInterruptTime` | ReactOS | `QueryPerformanceCounter` (also counts time asleep) |
| `GetTickCount64` | ReactOS | `GetTickCount` (wraps after 49.7 days) |
| `WaitOnAddress`, `WakeByAddress*` | Windows 7, ReactOS | the waiting thread re-reads the word, yielding and then sleeping 1 ms |

The translator's own lock is a spinlock, so SRW locks are not needed. The
last fallback makes a contended lock or a thread join take up to a
millisecond longer. Set `PXX_WINABI_PRE8=1` to use every fallback on a
newer system; `make test-windows` runs a few time, socket and thread tests
that way under Wine.

### Tested on ReactOS

The `make test-windows` programs were also run inside the ReactOS x64
nightly live CD (kernel "0.4.16-amd64-dev", Build 20260429, under qemu with
no network adapter): 78 of 83 give the same output as on Linux. The
translator works around three ReactOS behaviours:

- Its loader ignores the TLS directory's `SizeOfZeroFill` and allocates only
  the raw template, so the image now carries the whole thread-local block as
  zero bytes of raw data, as MSVC's linker does.
- A non-blocking `accept` with nothing pending returns `INVALID_SOCKET`
  zero-extended to `0x00000000FFFFFFFF` and sets no error; the translator
  reads that as `EAGAIN`.
- A refused non-blocking `connect` shows in Winsock's except set but leaves
  `SO_ERROR` at 0; the translator reports `ECONNREFUSED`.

Known differences there:

- ReactOS has no IPv6: the IPv6 tests report that and skip.
- A TCP listener bound to `0.0.0.0` does not get connections made to
  `127.0.0.1` (seen with no network adapter); bind the listener to
  `127.0.0.1` for local use. `test_asyncudp` waits for ever on this and is
  left out.
- A stack overflow ends the program (exit 128) instead of raising an
  exception; see "Not supported yet".
- With no page file, `sysinfo` reports no swap.

## How it works

The design is the same as the BSD targets (see
[FreeBSD and the BSDs](./freebsd.md)). The runtime is written against the
Linux system-call interface, and under `--os=windows` every system call goes
to a small translator compiled into the program
(`compiler/builtin/winabi.pas`). The translator answers it with kernel32
calls. Windows has no stable system-call numbers (they change between
builds), so kernel32 is the bottom layer rather than the kernel.

Five things differ from the BSD ports:

- **The file format.** `compiler/pewriter.inc` writes the PE image. It is
  laid out like the ELF one, with the code at RVA `0x1000` and the data
  after it. Imports go through the Import Address Table, which takes the
  place of the GOT slots the x86-64 external call already reads. The image
  loads at a fixed base (`0x400000`) with no relocations, so there is no
  ASLR yet.
- **The calling convention.** pxx code keeps the System V convention
  internally. Each call to a DLL function converts at the call site: the
  first four arguments move to `rcx`, `rdx`, `r8` and `r9`, the fifth and
  sixth go to the stack above 32 bytes of shadow space, and stacked
  arguments already land where Windows expects them. A call with a
  floating-point argument is rebuilt argument by argument instead, because
  Windows gives argument *n* the *n*-th slot whatever its type (`rcx` or
  `xmm0`, `rdx` or `xmm1`, and so on, then the stack), where System V
  counts integers and floats apart. A float among the first four also goes
  into its integer register, which is what a variadic Windows function
  such as `sprintf` reads. Float results come back in `xmm0` under both.
- **Thread-local storage.** A Windows program cannot point `fs` or `gs` at
  its own block, because `gs` is the thread environment block. The block
  is the image's PE TLS data instead, which the loader allocates for every
  thread. Code reaches it through the TEB (`gs:[0x58]`, then index 0),
  which costs two loads where Linux needs none.
- **Threads.** `clone` becomes `CreateThread`. The new thread moves onto
  the stack the runtime gave it, so it starts exactly where a Linux clone
  child would. `futex` becomes `WaitOnAddress` and `WakeByAddress*`, and
  a thread's exit wakes its joiner as Linux's `CLONE_CHILD_CLEARTID` does.
  Threads need `--threadsafe`, as on Linux.
- **The stack.** The image commits its whole 8 MiB stack at load time.
  Windows grows a stack one guard page at a time, and pxx functions do not
  probe their frames, so a frame larger than 4 KiB would otherwise skip the
  guard page and crash.

## What works

Each item is checked against the Linux build of the same test by `make
test-windows` (run under Wine through `tools/vm/wine.sh`):

- console output and input
- the heap
- exceptions
- time and `Sleep`
- command-line arguments (`ParamCount`/`ParamStr`, split by the Microsoft
  C runtime's quoting rules, and converted to UTF-8)
- environment variables
- exit codes and runtime errors
- files: open/create/truncate/append, read and write, seek,
  `pread`/`pwrite` and their vector forms, `stat`/`fstat`, rename, delete,
  `ftruncate`, `fsync`, `dup`/`dup2`, and pipes
- directories: create, remove, list (`getdents64` over `FindFirstFileW`),
  the current directory, and the `*at` calls relative to a directory fd

- `select`, `poll` and their `p` forms, on the console, pipes, files and
  sockets
- sockets (TCP and UDP, IPv4 and IPv6) over Winsock: `connect`, `bind`,
  `listen`, `accept`, the send and receive calls, `shutdown`, the socket
  options the runtime uses, non-blocking mode (`O_NONBLOCK`, `SOCK_NONBLOCK`,
  `MSG_DONTWAIT`), `socketpair`, and the runtime's sockets, net, HTTP and
  async DNS units
- `epoll`, `timerfd` and `eventfd`, emulated, so the coroutine scheduler and
  its reactor run (the async echo, UDP and timer tests)
- non-blocking pipes (`pipe2` with `O_NONBLOCK`, `fcntl`), and `SIGPIPE` on a
  write to a pipe or socket whose reader has gone, as on Linux
- starting programs: `ExecuteProcess` and the other SysUtils process calls,
  and Nil Python's `subprocess` (`run`, `Popen`, pipes in both directions,
  return codes, `FileNotFoundError`), with `wait4` and `kill`

Windows has no `fork`, so the runtime's one spawn routine
(`PalBackendVforkAndExec3`) passes the whole request to the translator,
which calls `CreateProcessW` instead of forking and `exec`ing. The argument
list is quoted so that the child's C runtime splits it back into the same
strings. A program named without a path is looked up on `PATH` (separated by
`;`, with or without `.exe`), then by `CreateProcessW` itself. A child ended
by `kill` reports that signal to `wait`, as on Linux. A C program's own
`fork()` answers `ENOSYS`.

`select`, `poll` and `epoll_wait` check each fd, then wait in Winsock's
`select` on the sockets among them, which wakes as soon as one is ready.
Windows has no one call that also covers consoles and pipes, so when one of
those is in the set the wait is cut to a few milliseconds and the check
repeats.

Sockets keep Linux's defaults where Windows differs: an IPv6 socket also
takes IPv4 (`IPV6_V6ONLY` off), a UDP socket ignores the ICMP "port
unreachable" that Windows would report on the next receive, and an accepted
socket does not inherit the listener's non-blocking mode. `SO_REUSEADDR` and
`SO_REUSEPORT` are recorded but not passed on: Windows already lets a server
rebind a port that is in `TIME_WAIT`, and its own `SO_REUSEADDR` would let a
second socket take a port that is in use. `socketpair` is a connected pair
of loopback TCP (or UDP) sockets.

Signals:

- **Hardware faults** (access violation, division by zero, floating-point
  traps, illegal instruction) reach the program's handler as `SIGSEGV`,
  `SIGFPE` and so on, with the same `siginfo` and register context as on
  Linux. So a nil access or a call through a bad pointer becomes a Pascal
  exception where it does on Linux. A fault with no handler ends the
  process with exit code 128 + the signal number.
- **`kill` and `raise` to the program itself** run the handler at once, or
  apply the default action (end the process, or ignore for `SIGCHLD` and
  the other signals Linux ignores). `sigprocmask` blocks for real, per
  thread, and a new thread inherits its creator's mask. Blocked signals
  stay pending for `sigtimedwait`, `sigwait`, `sigsuspend` and
  `sigpending`.
- **A signal sent to another thread** (`tkill`, `pthread_kill`) runs on
  that thread when it next unblocks the signal or makes a system call.
  Windows has no way to interrupt a thread with a handler, so a thread
  that loops without system calls, or waits inside one, sees it late.
- **Ctrl-C** is `SIGINT`, Ctrl-Break `SIGQUIT` and closing the console
  `SIGHUP`, once the program sets a handler (or `SIG_IGN`) for one of
  them. Windows runs that handler on a thread of its own, so it really is
  asynchronous. Checked by hand under Wine, not in the test target.

Paths are converted from UTF-8 to UTF-16, and `/` works as a separator.
`/dev/null` becomes `NUL`. An absolute Unix path such as `/tmp/x` is taken
on the current drive. Under Wine that is drive `Z:`, the Unix root, so the
path means what it means on Linux.

## Not supported yet

- **Refused at compile time:** `-g`, `--shared`, `--emit-obj`,
  `--rtl-libc`, and CPUs other than x86-64.
- **Not supported:** C's `fork()`, process groups, symbolic links, file
  modes (`chmod` succeeds and does nothing), and `mmap` of a file.
- **Signals between processes:** `kill` on another program ends it
  (`TerminateProcess`) whatever the signal; it cannot run that program's
  handler. There is no alternate signal stack, and a stack overflow has no
  room left to run a handler in.
- **Sockets:** no control messages (`SCM_RIGHTS` cannot pass an fd to
  another process), and `MSG_TRUNC` does not report a truncated datagram's
  full length. A blocking socket call cannot be interrupted by a signal.
  The runtime's DNS resolver reads `/etc/hosts` and `/etc/resolv.conf`,
  which Windows does not have.
- **Calling other libraries:** `external 'libc.so.6'` and other Linux
  libraries cannot work on Windows. `external 'user32.dll'` and other DLLs
  do work, with integer, pointer and floating-point arguments. A record
  passed by value is not converted (Windows passes one larger than 8 bytes
  by reference), and a callback that Windows calls with floating-point
  arguments does not receive them.

A system call the translator does not map returns `ENOSYS`. Set
`PXX_WINABI_TRACE=1` in the environment to have each one named on stderr.

The work log is in `devdocs/progress/working/feature-port-windows-pe.md`.
