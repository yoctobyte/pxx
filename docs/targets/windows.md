---
title: Windows (experimental)
order: 62
---

# Windows (experimental)

`--os=windows` (or its other name `--os=nt`) writes a Windows x64 console
executable (PE32+) from Pascal, C or Nil Python. It is **EXPERIMENTAL**, like every target except Linux.

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
harness is in `tools/vm/reactos/`: `rossnap.sh` boots the live CD once and
saves a qemu snapshot, `rosbatch.sh test...` then runs a batch from it in
about ten seconds plus the programs' own time. The translator works around
three ReactOS behaviours:

- Its loader ignores the TLS directory's `SizeOfZeroFill` and allocates only
  the raw template, so the image now carries the whole thread-local block as
  zero bytes of raw data, as MSVC's linker does.
- A non-blocking `accept` with nothing pending returns `INVALID_SOCKET`
  zero-extended to `0x00000000FFFFFFFF` and sets no error; the translator
  reads that as `EAGAIN`.
- A refused non-blocking `connect` shows in Winsock's except set but leaves
  `SO_ERROR` at 0; the translator reports `ECONNREFUSED`.

The compiler itself builds for Windows (`--os=windows compiler/compiler.pas`)
and works there: under Wine and inside ReactOS it compiled `hello.pas` to a
Windows `.exe` that runs. A compiler built this way makes Windows
programs by default (`pascal26 hello.pas` writes `hello.exe`; `--os=linux`
still gives a Linux ELF), and `--version` reports `host: x86-64 nt` (NT, whichever
system provides it: Windows, ReactOS or Wine).
It finds `lib/` and `compiler/builtin/` (where `winabi` lives) the usual
way: installed as `<root>/compiler/pascal26.exe` beside `<root>/lib`, or
through `PXX_HOME`.
It also compiles itself there: on 2026-11-15, under Wine, the Windows build
compiled `compiler/compiler.pas` in 42 s to an `.exe` byte-identical to the
one the Linux compiler makes with `--os=windows`. The guard that refuses an
output naming an input also works there: `g/sub/../t.pas` and `G/T.PAS`
(Windows names ignore case) both count as `g/t.pas`.

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
  prefers the base `0x400000` and carries a `.reloc` section that lists
  every absolute address in it (method slots, data pointers, C initialisers,
  the TLS directory, the code's 64-bit immediates), so it is marked
  `DYNAMIC_BASE` and Windows may load it anywhere below 4 GiB (ASLR, without
  high-entropy addresses). `--image-base=0x7ffe0000` gives a base the loader
  has to move, which is how `make test-windows` checks the relocations.
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

- console output and input; UTF-8 text written to a console window is
  shown as UTF-8 (converted for `WriteConsoleW`, also when a character is
  split across two writes), while output to a file or a pipe is left as
  the bytes the program wrote
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
- Nil Python's `os.path` on Windows paths: `basename`, `dirname`, `split`,
  `splitext`, `isabs`, `abspath` and `normpath` take `\` as a separator and
  keep a drive (`Z:`) in front, as CPython's `ntpath` does. Unlike CPython,
  `join`, `abspath` and `normpath` write `/` (Windows accepts it), so a
  program prints the same paths as on Linux: `Z:/dir/prog.exe`

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

`/proc` has six files: `/proc/self/environ`, `/proc/self/exe` (the
program's own file), `/proc/self/fdinfo/N` (the volume serial number as
`mnt_id` and the file index as `ino`, which the compiler's output guard
compares), `/proc/mounts` (one line per local drive, `C: / ntfs rw 0 0`,
with the current drive on `/` and the others on `D:/` and so on) and the
aggregate `cpu` line of `/proc/stat` (`GetSystemTimes`), and
`/proc/net/dev` (the interface names, every counter 0).
Every other `/proc` path is `ENOENT`, also under Wine, whose drive `Z:` would
otherwise show Linux's own `/proc`.

The runtime's DNS resolver reads `/etc/hosts` and `/etc/resolv.conf`. On
Windows `/etc/hosts` is the system's own hosts file
(`<system directory>\drivers\etc\hosts`), and `/etc/resolv.conf` is made
up when it is opened: a `nameserver` line for each DNS server Windows is set
to use, and a `search` line for its domain, from `GetNetworkParams` in
`iphlpapi.dll` (loaded only then, so the image still imports kernel32 and
ws2_32 alone).

Network interfaces (`if_nameindex`, `if_nametoindex`, `getifaddrs`) come
from `GetAdaptersAddresses`, from the same DLL loaded the same way. They
are IPv4 adapters only, as Linux's `SIOCGIFCONF` lists them. The runtime
answers the Linux `SIOCGIFCONF`, `SIOCGIFFLAGS`, `SIOCGIFADDR`,
`SIOCGIFNETMASK`, `SIOCGIFBRDADDR`, `SIOCGIFINDEX` and `SIOCGIFNAME`
ioctls itself. A name is Windows' own (`loopback_0`, `ethernet_32768`,
from `ConvertInterfaceLuidToNameA`). Where Windows has no such name
(ReactOS and XP), a loopback is `lo` and any other adapter `if<index>`.
ReactOS reports index 0 for its loopback, which would end
`if_nameindex`'s list, so such an adapter gets the next free index.

Paths are converted from UTF-8 to UTF-16, and `/` works as a separator.
`/dev/null` becomes `NUL`. An absolute Unix path such as `/tmp/x` is taken
on the current drive. Under Wine that is drive `Z:`, the Unix root, so the
path means what it means on Linux.

## Not supported yet

- **Refused at compile time:** `-g`, `--emit-obj`, `--rtl-libc`, and
  CPUs other than x86-64.
- **DLLs:** `--shared` (or an output name ending in `.dll`) writes a DLL.
  A Pascal `library` exports its `cdecl` routines and the ones its
  `exports` clause names. A C file exports its functions that are not
  `static`, and none of lib/crtl's. Loading the DLL runs its
  initialisation: the global initialisers, the units' `initialization`
  sections and the library's main body, as a Linux `.so` does.
  `finalization` does not run at unload. Each export is a stub that jumps
  to an adapter, which takes the Microsoft convention and calls the routine
  (the callback adapters, built by DllMain). Threadvars work, through the
  TLS index the loader gives the DLL; build with `--threadsafe` when
  threads call in. The DLL prefers the base `0x10000000` and carries
  `.reloc`. Refused at compile time: an export with more than 14
  parameters, or with a record parameter or result by value. Tested with
  pxx executables calling pxx DLLs (`test/test_nt_dll_built_by_pxx.pas`)
  under Wine in `make test-windows`, and once by hand on ReactOS
  (`tools/vm/reactos/rosbatch.sh -f <dll>...`). A pxx DLL also exports
  `__pxx_dll_table`, which `dlsym` uses (below). NOT TESTED: a DLL loaded
  by a program another compiler made.
- **Loading a library at run time:** C's `dlopen`, `dlsym`, `dlclose` and
  `dlerror`, and Pascal's `dynlibs` (`LoadLibrary`, `GetProcedureAddress`,
  `UnloadLibrary`), use Windows' loader (`LoadLibraryA`, `GetProcAddress`,
  `FreeLibrary`). The address `dlsym` returns is called with pxx's own
  convention, so:
  - from a DLL pxx wrote, it is the routine itself, and every signature
    works;
  - from any other DLL, it is an adapter to the Microsoft convention, built
    once per address. The adapter is right for integer and pointer
    arguments (up to 14), for floating-point arguments when every argument
    is one (up to 4), and for a result in `rax` or `xmm0`. It is wrong for
    a routine that mixes integer and floating-point arguments, for a fifth
    floating-point argument, for a record passed by value, and for a record
    result of 9 to 16 bytes. For those, declare the routine
    `external 'x.dll'` instead: a call to a declared routine is converted
    with its full signature.

  `dlopen(NULL)` is refused, as on Linux. Tested under Wine
  (`test/c_nt_dlopen.c`, `test/test_nt_dynlibs.pas`).
- **Not supported:** C's `fork()` and process groups.
- **Symbolic links** are Windows' own (`CreateSymbolicLinkW`). Making one
  needs the privilege, or Windows 10's developer mode; without it `symlink`
  says `EPERM`. `readlink` and `lstat` read the reparse point of a symbolic
  link or a junction, and `stat` follows it. Any other reparse point, such
  as a cloud placeholder, counts as a plain file, so `stat` does not fetch
  its contents. NOT TESTED where it can work: Wine's
  `CreateSymbolicLinkW` succeeds without making anything (the translator
  checks, and says `EPERM`), Wine shows a Unix link as its target, and the
  ReactOS live CD cannot make links. `test/c_os_symlink.c` checks it on a
  Windows that can.
- **File modes:** Windows keeps one permission bit, the read-only attribute.
  `chmod` with no write bit sets it, and with any write bit clears it; `stat`
  reads it back as `0444` or `0644`. The other bits are dropped. `fchmod`
  succeeds and changes nothing.
- **`mmap` of a file** is a view of a file mapping (`CreateFileMappingW`,
  `MapViewOfFile`): `MAP_SHARED` with `PROT_WRITE` writes through to the
  file, `MAP_PRIVATE` is copy-on-write, and `msync` flushes the view. Not
  supported: `PROT_EXEC` (the view is not executable) and `MAP_FIXED`.
  Windows cannot map past a file's end, so the view stops there, and
  touching the rest faults (Linux faults past the last page). An empty file
  maps as zeroed private memory.
- **Signals between processes:** `kill` on another program ends it
  (`TerminateProcess`) whatever the signal; it cannot run that program's
  handler. There is no alternate signal stack, and a stack overflow has no
  room left to run a handler in.
- **Sockets:** no control messages (`SCM_RIGHTS` cannot pass an fd to
  another process), and `MSG_TRUNC` does not report a truncated datagram's
  full length. A blocking socket call cannot be interrupted by a signal.
- **Calling other libraries:** `external 'libc.so.6'` and other Linux
  libraries cannot work on Windows. `external 'user32.dll'` and other DLLs
  do work, with integer, pointer, floating-point and record arguments. A
  record passed by value follows the Microsoft rule: one of 1, 2, 4 or 8
  bytes travels as an integer, any other size as a pointer to a copy the
  caller makes. A record result of 1, 2, 4 or 8 bytes comes back in `rax`,
  and a larger one through a hidden first argument.
- **Callbacks:** a routine of the program passed straight to a DLL routine
  (`qsort(@v[0], n, 4, @Cmp)`, `EnumWindows(@Cb, 0)`) is handed over as an
  adapter that takes the Microsoft convention and calls the routine,
  floating-point and stack arguments included (up to 14 parameters). The
  program's own calls to the routine are unchanged. Declare a callback
  `stdcall`, as Delphi and Free Pascal code does, and every address taken
  of it is the adapter, so one stored first also works: a variable, or a
  record field such as a window class's `lpfnWndProc`. Without `stdcall`,
  only an address passed straight into the call is adapted, and one stored
  first is the routine itself, which crashes when Windows calls it. Calling
  a `stdcall` routine through a procedural variable from Pascal does not
  work: the variable holds the adapter, which expects the Microsoft
  convention. Call it by name. A record passed by value to a callback is not
  converted.

A system call the translator does not map returns `ENOSYS`. Set
`PXX_WINABI_TRACE=1` in the environment to have each one named on stderr.

The work log is in `devdocs/progress/working/feature-port-windows-pe.md`.
