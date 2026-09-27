---
title: Known issues in beta 0.1
order: 94
---

# Known issues in beta 0.1 "Blaise"

These are the problems we know about in the beta 0.1 compiler, **pin v441**
(commit `5c1696ca79`, compiler sha256 `4ebfa2d047a2…`). Each row says which
compiler it was measured with. Rows measured on the earlier draft pin v425 say
so; nothing in this release is known to have changed them.

Problems that **compile and silently give a wrong answer** come first, because a
refusal at least tells you something is wrong.

## Silently wrong

### C: `long double` is 8 bytes

GCC's `long double` is 16 bytes on x86-64; PXX's is 8, the same as `double`. A
single program is consistent with itself, but a struct that contains one has a
different size from GCC's: `struct { char c; long double y; }` is 16 bytes here
and 32 under GCC. That matters as soon as such a struct crosses into
GCC-compiled code or into a file format. (Measured with v425.)

### C: an initialised `__thread` variable reads 0 in other threads

`__thread int tl = 7;` reads 7 in `main` and 0 in a thread started with
`pthread_create`. **Workaround:** assign the value at the start of each thread.
A fix in progress is parked in the repository as
`devdocs/dev/parked-patches/tls-init-image-reaches-every-thread-wip.patch`.
(Measured with v425.)

### C: a struct field that points at an array typedef

With `typedef float vec4[4]; typedef vec4 mat4[4];`, a struct field declared
as `mat4 *p;` or `mat4 *m[3];` does not know the shape of what it points at:
`sizeof *s.p` is 4 where GCC gives 64, `(*s.p)[2][2]` reads the wrong
element, and `(*s.m[0])[1][1]` crashes. The same declarations as variables or
parameters are right. **Workaround:** copy the field into a local of the same
type first (`mat4 *p = s.p;`) and use that. (Measured with v441 and with the
compiler that fixed the variable spellings.)

### ESP: bare-metal images do not run on a real chip

Images built with `--esp-profile=bare` fault on the first byte access to a
global or a string, and their UART output is lost. Measured on an ESP32-S3 with
v424; a bare ESP32-C3 image has never been run on silicon. They run under
Espressif's QEMU (`qemu-system-xtensa` and `qemu-system-riscv32`), which is what
the bare profile is for. esptool cannot convert a bare ELF either, since it has
no section headers. **Workaround:** on hardware, build the program as an
ESP-IDF component (the default); see [ESP32](../targets/esp32.md).

## Memory leaks

Memory leaks were treated as release blockers for this beta. Before the release
every leak test in the tree was re-run, and each ran beside a deliberate leak
to prove it could catch one:

- all 164 automated leak checks in the test suite;
- 49 Pascal shapes on seven targets (x86-64, i386, aarch64, arm32, riscv32,
  and Xtensa in both calling conventions) at `-O0` to `-O3`, covering strings,
  dynamic arrays, managed records, interfaces, closures, exceptions, classes,
  generics, `TStringList` and `Format`;
- threads (`TThread` with managed fields, a `TStringList` under a critical
  section) on x86-64, i386, aarch64 and arm32;
- real programs: uforth, eleven Pascal examples, and Lua 5.4 scripts.

**No open compiler-caused leak was known when v441 was released.** The sweep
found five, and all five are fixed in this release. If you are on an older pin,
use the workaround. One more was found after the release; it is listed after
these five.

- **`Dispose(p)` did not finalize the thing `p` points at.** When `p` points at
  a record with a string, dynamic-array, interface or `Variant` field, or at a
  string, dynamic array, interface or `Variant` itself, 16 to 160 bytes were
  lost per `Dispose`, on every target. **Older pins:** call `Finalize(p^)`
  before `Dispose(p)`.
- **`Finalize` of a whole fixed array of managed elements released only the
  first element.** **Older pins:** finalize the elements in a loop.
- **`Dispose(F())` did not finalize the pointee when the pointer came from a
  function call.** **Older pins:** assign the pointer to a variable and dispose
  of that.
- **Nil Python: a `for` loop target that already held an object** kept one
  object per iteration. **Older pins:** give the loop variable a fresh name.
- **Nil Python: a `lambda` passed straight as an argument**, as in
  `sorted(xs, key=lambda v: -v)`, kept one closure per call. **Older pins:** bind
  the lambda to a name first.

Found after the release, on 2026-09-27, and **open in v441**:

- **Nil Python: `list.clear()` and `dict.clear()` did not release what they
  dropped.** The elements, or the keys and values, stayed allocated after the
  list or dict itself was freed. A function that fills a list with 20 strings
  and clears it lost 20 strings per call. A buffer cleared and refilled in a
  loop does not grow, because refilling releases the old elements, but the
  last contents are lost when the buffer goes away. Fixed after v441, in the
  runtime that the compiler links into every Nil Python program. **On v441:**
  assign a new empty container (`buf = []`, `d = {}`) instead of calling
  `clear()`.

Program-level global variables are not finalized when the program exits. This
is a one-time cost at exit, not a leak that grows while the program runs.

Nil Python: a string temporary built by a module-level statement, such as
`print("n=" + str(n))` outside any function, is kept until that statement runs
again. That is at most one string per source line, and a loop reuses it, so
the cost is bounded by the program's length and does not grow while it runs.
Inside a function, temporaries are released when the statement ends.

A list that a statement creates, such as `kept = []`, stays allocated until
that same statement runs again or the function returns. That holds even after
the name is bound to something else (`kept = []` a second time on another
line, `kept = None`, `del kept`). It does not add up in a loop, but a function
that fills a list and then drops it keeps the contents until it returns. On an
ESP32-C3 with about 70 KB free, 34 kept HTTP responses (about 1.4 KB each) held
that way ran the heap low enough that Wi-Fi stopped working. Return from the
function, or let it end, to get the memory back.

### ESP networking

Networking was soaked under Espressif's QEMU with the v440 compiler (v441
differs from it only in the `Dispose(F())` fix). None of these runs showed
memory or sockets growing:

| what ran | chip | result |
| --- | --- | --- |
| 10,000 HTTP requests with `urequests` (Nil Python) | ESP32-S3 | 64 bytes in total over 10,000 requests |
| 1,000 sessions each of `ntptime`, `umqtt.simple` and `umqtt.robust` (Nil Python) | ESP32-S3 | 0 bytes per session |
| 3,000 MQTT sessions with `umqtt.simple` (Nil Python) | ESP32-C3 | the same socket number every session; heap flat after the first 25 |
| 320 TCP connections over loopback, server and client in Pascal | ESP32-S3 | 0 bytes over 40 passes |
| 300 HTTPS requests with `urequests` (Nil Python; needs a compiler newer than v441) | ESP32-S3 | 68 bytes in total over 300 requests |

Each run was checked against a deliberate leak, which it caught. An earlier
reading of about 0.6 bytes per pass on the Nil Python example programs turned
out to be the soak's own report lines, one kept string per checkpoint line (see
the Nil Python paragraph above). With those lines moved into a function, the
four Nil Python examples keep 0 bytes after 10, 160, 640 and 1,280 passes on
both chips, with v441, beside a deliberate leak that reads 76 bytes per pass.
A MicroPython-style main loop written at module level, making 1,000 requests
with a `print` each time, holds about 1.6 KB once (the last response, still
bound to its variable, as in CPython) and then stays level.

**TLS on ESP is client-only, and does not check certificates by default.**
`ssl.wrap_socket` and `SSLContext` work, so `urequests.get("https://...")` and
`MQTTClient(..., ssl=True)` do too, but, as in MicroPython, the server's
certificate is only checked when the program asks for `CERT_REQUIRED` and
passes the authority it trusts; there are none on the chip. See
[TLS on ESP](../library/esp.md#tls). A Nil Python program on a desktop has no
`ssl` module, so `urequests` there refuses `https://` URLs with a `ValueError`;
desktop Pascal programs have TLS through the `http` unit.

Two limits apply to these measurements:

- **Over real Wi-Fi, only the ESP32-C3 has been measured**, and only with
  `urequests`. The rows above ran over QEMU's emulated Ethernet. On
  2026-09-27, one ESP32-C3 board with the v441 compiler, joined to a home
  Wi-Fi network, fetched a page from a PC on that network 1,000 times. Free
  heap stayed within 400 bytes of where it started, with no upward trend, and
  ended 364 bytes higher. A second run of 300 fetches grew by 20 bytes, and after the
  function holding the responses returned and 130 seconds passed, all of it
  had come back. Its positive control kept 20 responses, which cost 1,434
  bytes each.
- **Long network runs on the ESP32-C3 stop under QEMU** after a few hundred to
  a few thousand requests: the program stops making progress, although memory
  and sockets are not exhausted. At the stall, the emulated network card holds
  received frames and has an interrupt pending that is never delivered, so the
  program waits forever for data that has already arrived. This happens below
  the compiled program, in the emulator's network path, and has not been seen
  on the ESP32-S3. On a physical C3 over real Wi-Fi it did not happen: about
  1,700 requests over three runs on 2026-09-27, with no stall. Under QEMU it
  comes much sooner over TLS: four of five HTTPS runs on the C3 stopped within
  their first twenty requests, with a compiler from before the HTTPS leak fix
  and one from after it alike, so no HTTPS memory figure for the C3 is given.

## Fixed in this release

These were wrong in the earlier draft pin v425 and are fixed in v441.

- **C: a member access on a comma expression read the wrong value.**
  `((void) f(), &t[i])->value` read garbage; v441 reads `t[i].value` (checked
  with v441). stb_ds's `shget` has this shape.
- **C: compound literals of an array type were refused**, such as
  `(vec4){1, 2, 3, 4}` for `typedef float vec4[4]` and `(mat4){...}` for a typedef
  of array typedefs (cglm's `GLM_MAT4_IDENTITY`). v441 accepts them (checked
  with v441).
- **C: re-locking a recursive `pthread` mutex hung**, so SQLite built with
  `--threadsafe` hung in `sqlite3_open`. Fixed in the C runtime (`3f28aafab`).
- **Pascal: a designator containing a function call was evaluated more than
  once.** `a[Pick(i)].Free` called `Pick` four times (v425 too), and on the
  interim pins v439 and v440 `Dispose(a[F()])` called `F` three times. v441
  calls it once.
- **ESP: an uncaught exception did not report itself.** The program now prints
  `Unhandled exception: <Class>: <Message>`, as on a desktop, before it stops
  (`7eeb3d755`). Whether an ESP program should stop or restart after that has
  not been decided; it stops.
- **The five memory leaks** listed under [Memory leaks](#memory-leaks).

These were wrong in v424 and fixed in v425, and so are fixed here too:

- **libc `printf` output was lost at exit** in a Pascal program calling libc's
  `printf` through a `varargs` external.
- **`writeln` of a function result leaked** one string per call.
- **C `printf` with a `double` printed wrong values on riscv32** once the call
  had more arguments than fit in registers.
- **A wasm32 C program that includes `math.h` was refused** with
  `wasm: var-name pool full`.
- **A type named like a compiler-internal record got the wrong layout**
  (`TProc`, `TSymbol`).
- **An ESP32-S3 bare-metal program that declares a `Double` and uses managed
  strings** failed to build.
- **C `sizeof` of a multidimensional array, a typedef of array typedefs, and
  `sizeof (t)->key`** gave wrong sizes or were refused.

## Refused, with a message

These do not compile, or compile with a warning. None of them produces a wrong
answer silently. (Measured with v425.)

- **Pascal `threadvar` on i386** is refused: only x86-64, aarch64 and arm32
  provide per-thread storage.
- **C `__thread` on i386 and riscv32** compiles with a warning that every thread
  shares one copy. Single-threaded programs are unaffected.
- **C `setvbuf` with full or line buffering** returns nonzero: PXX's C streams
  are unbuffered, and the call says so rather than claiming success.
- **`--shared` on aarch64 and arm32** is refused with
  `shared-library output is x86-64 only`, as on i386.

## Optimisation levels

`-O2` is the default and the level the compiler proves on itself. `-O3` is
experimental: its differential check against `-O2` had two failing shards at
v439. Use `-O3` only if you check the output.

## By design: `Trunc` of an out-of-range float into a 32-bit integer

`Trunc(1e30)` stored in an `Int64` saturates to 9223372036854775807. Stored in
a `LongInt` it gives -1, the low 32 bits of that saturated value. This is the
same on every target, desktop and ESP (measured with v425). A float that does
not fit the integer type it is truncated into has no meaningful integer value;
test the range first if the input can be that large.

## By design: math errors

An embedded device should keep running when a sensor produces a value that
causes a math error. A desktop program should stop and say what happened. So
the two behave differently on purpose:

| | Desktop (Linux, all CPUs) | ESP32-S3 and ESP32-C3 |
| --- | --- | --- |
| Pascal and C: integer `div` / `mod` by zero | runtime error 200, the program stops | gives 0, the program continues |
| Pascal and C: float division by zero | Inf or NaN | Inf or NaN |
| Nil Python: `//` and `%` by zero | `ZeroDivisionError`, except in some shapes that stop with runtime error 200 (see the [Nil Python limits](../targets/nil-python.md#known-limits)) | gives 0, the program continues |
| Nil Python: float `/` by zero | `ZeroDivisionError`, as in CPython | Inf |

Each cell was measured on v425. The desktop column was run on x86-64, i386,
aarch64, arm32 and riscv32 Linux (Nil Python has no hosted riscv32). The ESP
column was measured under Espressif's QEMU on both chips, for Pascal, C and
Nil Python. This is not a bug to be fixed: if you need a zero divisor to stop an ESP program,
test the divisor yourself.

## Nil Python

Nil Python is best effort in this beta. It compiles Python-shaped source ahead
of time and is not CPython: CPython compatibility is not a goal of this
release, and it has a real backlog. Its measured list of limits is kept on the
[Nil Python page](../targets/nil-python.md#known-limits), and the deliberate
differences from CPython are recorded beside it. On ESP, the model is
MicroPython's assumptions about a small device, such as math errors not halting
the program. 14 of 16 common MicroPython drivers compile unchanged; see
[MicroPython](../library/micropython.md).

## Reporting a problem

Open an issue at <https://github.com/yoctobyte/pxx/issues> with the smallest
source file that shows the problem, the exact command you ran (including any
`--target=`), what you expected and what you got, and the output of
`./pxx --doctor` with the commit of your checkout (`git log -1 --format=%h`).
A program that compiles and gives a wrong answer is the most useful report you
can send.
