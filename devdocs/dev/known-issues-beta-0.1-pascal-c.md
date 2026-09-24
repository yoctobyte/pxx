# Known issues, beta 0.1: Pascal and C

Measured 2026-09-24 by frankS. Every row below was run, not recalled. Each row
names the targets it was measured on and the binaries it was measured with:

- **v423**: pin v423, compiler sha256 `113a515bbdc9`, the pin the beta notes are
  stamped with.
- **HEAD**: `compiler/pascal26` sha256 `448395e492db`, built from origin/master
  plus the by-value-parameter fix (see "Fixed after v423").

A row that says "both" reproduced on both binaries. The oracle is `fpc -Mobjfpc`
3.2.2 for Pascal and `gcc` for C, on x86-64.

Silent-wrong rows come first. A refusal names the problem; a silent row does not.

---

## Silently wrong

### Pascal, all targets: a record named like a compiler-internal record gets the compiler's layout

- What you see: `type TProc = record A: array[0..99] of Int64; end;` gives
  `SizeOf(TProc)` = 1344 (fpc: 800), with no diagnostic. The same happens for
  thirteen other names, TSymbol among them.
- Workaround: rename the type.
- Measured on x86-64, both binaries.
- Ticket: bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type.

### C, all targets: `long double` is 8 bytes; gcc's is 16

- `sizeof(long double)` = 8. `struct { char c; long double y; }` is 16 here
  (12 on i386) and 32 under gcc.
- Self-consistent inside one program; wrong as soon as the layout crosses into
  gcc-compiled code or a file format.
- Measured on x86-64, i386, arm32, aarch64 and riscv32, both binaries.
- Ticket: bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc.

### C, all threaded targets: an INITIALISED `__thread` variable reads 0 in every thread but the first

- `__thread int tl = 7;` reads 7 in `main` and 0 in a `pthread_create`d thread
  (gcc: 7 in both).
- Workaround: assign the value at the start of each thread.
- Measured on x86-64, both binaries.
- A fix exists as a parked work-in-progress stash ("frankS: tls init image
  WIP"). Recorded on
  bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there.

### Pascal and NilPy, ESP (esp32c3, esp32s3): an uncaught exception does not report itself

- A desktop build prints `Unhandled exception` and exits.
- esp32c3 (IDF) prints `Guru Meditation Error ... Environment call from
  M-mode` and reboots in a loop. The NilPy census counted 58 to 66 boots in 20 s.
- esp32s3 stops after the last line printed, with no message.
- Workaround: catch at the top of the program.
- Measured under Espressif QEMU, HEAD.

### Pascal, ESP: `Trunc` of an out-of-range float into a 32-bit integer wraps

- `Trunc(1e30)` stored in a `LongInt` gives -1, the low bits. The same
  `Trunc(1e30)` into an `Int64` saturates to 9223372036854775807, and NaN gives 0.
- This is the ESP "keep running on a math error" policy; only the 32-bit
  narrowing is inconsistent.
- Measured on esp32c3 and esp32s3, HEAD.

---

## Refuses, with a message that names the problem

- **Pascal `threadvar` on i386** refuses at compile time: "threadvar needs a
  per-thread block, and only x86-64, aarch64 and arm32 install one". riscv32 has
  no threads.
- **C `__thread` on i386 and riscv32** compiles with a warning saying every
  thread shares one copy. Single-threaded code is unaffected.
- **C `setvbuf(..., _IOFBF/_IOLBF, ...)`** returns nonzero: crtl streams are
  unbuffered, and it now says so instead of claiming success. `_IONBF` returns 0.
- **Integer division by zero on a desktop target** is runtime error 200, as in
  fpc (`EDivByZero` with sysutils). On ESP it gives 0 and the program continues,
  by the owner's decision (decide-int-div-zero-behavior-unification).

---

## Fixed after v423 (present in v423, gone at HEAD)

- **By-value string or dynamic-array parameter.**
  - A callee writing into a by-value string changed the caller's string: the
    textbook `UpperStr` returned the right value AND upper-cased the caller's.
    Every native target.
  - A callee that rebound such a parameter leaked one block per call.
  - Fixed on x86-64, i386, arm32, aarch64, riscv32, esp32c3, esp32s3 and
    wasm32. On wasm32, `SetLength(a, 9)` on a by-value dynamic-array
    parameter also used to have no effect in the callee; that is fixed too.
- **Pascal `writeln` on wasm32.** `program t; begin writeln(6*7); end.` built
  with `ok:` and rc=0, then trapped under wasmtime (frankd-a3, v423 and
  `448395e492db`). It prints `42` now. A missing runtime helper on wasm32 now
  fails the build instead of producing a module that traps.
- **A `var` parameter accepted a variable of another width** and the callee
  wrote past it (`P(var x: Int64)` with a LongInt clobbered a neighbour). Now
  refused, as fpc does; overloads bind the exact-width row. `Val` with a
  narrow `code` or destination (a Word, a Single, a record field) wrote past it
  too and now matches fpc.
- **`examples/parallel/collatz`** printed `total steps = 0`. The bug was in the
  example: a local `n` hid `const N`. pxx now warns on that shape.
- **A program routine named like a System const** (`function MaxInt(A, B)`) was
  refused. v421 compiled it into a segfault.

## Fixed before v423 (in the 2026-09-06 draft's list, re-measured gone)

- A dynamic array of a class type passed as a parameter reads correctly.
- Writing the output to a missing directory fails with rc=1 and a message.
- C stdio on wasm32 builds and runs (`printf` under wasmtime).
- `setvbuf` no longer claims success it did not deliver (see above).

## Not a known issue, recorded so nobody re-files it

- `p := @s[1]; p^ := 'Z'` on a string assigned a literal segfaults. fpc also
  faults (runtime error 216): the literal is read-only in both.
- `c_crtl_wait.c` is red on borg only. borg's qemu 8.2.2 reports
  WIFCONTINUED/SIGCONT differently from plexus's 10.2.1, where it is green.
- `demos#00` and `lib-test#00` are red on borg only: host `/usr/include` typedef
  conflicts. They pass on plexus (frankh-c0's full run, 2026-09-22).
