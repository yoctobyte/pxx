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

## At a glance

Every open issue on this page, one line each. The rows below give the
details, the measurements and the workarounds.

**Silently wrong: compiles, and gives a wrong answer with no message**

- Pascal: `SetLength` past a `ShortString` or `string[N]`'s capacity, then filling it, writes over neighbouring variables and can crash (v441 to v451; fixed after v451): [row](#pascal-setlength-past-a-short-strings-capacity-overruns-it)
- C `long double` is 8 bytes, not GCC's 16: [row](#c-long-double-is-8-bytes)
- riscv32 and Xtensa (the ESP32 CPUs) flush subnormal doubles to zero: [row](#riscv32-and-xtensa-arithmetic-flushes-subnormal-doubles-to-zero)
- Nil Python: arithmetic on `None`, or a string minus a large integer, gives a number instead of `TypeError`: [Nil Python](#nil-python)
- Nil Python: `hex`, `oct` and `bin` of a `**` result past 64 bits: [Nil Python](#nil-python)
- Nil Python: `atexit.unregister(f)` with a def named directly leaves it registered: [Nil Python](#nil-python)
- Nil Python: a method called from `exec` code can get a truncated or wrong argument, and an `exec`'d `__body__` reads its parameters as `None`: [exec and eval](#exec-and-eval)

**Stops at run time**

- wasm32: integer division by zero stops the module instead of raising: [Stops at run time](#stops-at-run-time)
- Pascal: unary minus on a record compiles and then crashes (v441 to v451; fixed after v451): [Stops at run time](#stops-at-run-time)
- ESP: a bare-metal image faults on a real chip; use the ESP-IDF build: [row](#esp-bare-metal-images-do-not-run-on-a-real-chip)
- Nil Python: `raise` inside `exec`'d code cannot be caught: [exec and eval](#exec-and-eval)
- Nil Python on the ESP32-C3: sorting a list needs about as much free heap again as the list: [Nil Python](#nil-python)

**Refused, or not what you expect**

- Four refusals with a message (C `__thread` on riscv32, `setvbuf` buffering, `--shared` off x86-64, a Nil Python name holding a Pascal array): [Refused, with a message](#refused-with-a-message)
- Nil Python through `./pxx`: `import time`, `import string` and `import utime` find the C headers: [Nil Python](#nil-python)
- Nil Python: `exec` stores a def only when it is named `__body__`: [exec and eval](#exec-and-eval)
- Nil Python: `from X import *` does not compile: [Nil Python](#nil-python)
- HTTPS through the native TLS backend fails on most sites, because it cannot check a P-384 or SHA-384 signature (v441 to v451; fixed after v451); the OpenSSL backend works: [row](#native-tls-most-https-sites-fail-certificate-verification)
- `-O3` is experimental: [Optimisation levels](#optimisation-levels)

**Memory**

- Nil Python never frees a reference cycle; a module-level statement keeps its string temporary until it runs again; program globals are not finalized at exit: [Memory leaks](#memory-leaks)

**ESP networking**

- TLS on ESP does not check certificates unless the program asks: [ESP networking](#esp-networking)
- ESP32-C3 network runs stall under QEMU (the emulator, not the program): [ESP networking under load](#esp-networking-under-load)

**By design**

- `Trunc` of an out-of-range float into a 32-bit integer: [row](#by-design-trunc-of-an-out-of-range-float-into-a-32-bit-integer)
- Integer division by zero stops a desktop program and gives 0 on ESP: [Math errors](#by-design-math-errors)

**Unresolved:** one test row, riscv32 `wait4` under QEMU 8.2.2, is described at the start of [Fixed since v441](#fixed-since-v441).

## Silently wrong

One Pascal row comes first. Four more rows that give a wrong answer with no message are Nil Python rows, under [Nil Python](#nil-python): arithmetic on `None`, and three shapes of `exec`.

### Pascal: SetLength past a short string's capacity overruns it

A `ShortString` holds at most 255 characters and a `string[N]` at most N.
`SetLength` with a larger count, held in a variable, does not stop at that
capacity, so the loop that usually follows writes past the end of the
variable, over whatever the program keeps next to it, and can crash:

```pascal
program overrun;
var
  t: string[10];
  guard: Integer;
  n, i: Integer;
begin
  guard := 777;
  n := 50;
  SetLength(t, n);                          { Length(t) is now 50, not 10 }
  for i := 1 to Length(t) do t[i] := 'x';   { writes 40 bytes past t }
  writeln('var ', Length(t), ' ', guard);
end.
```

Measured on 2026-09-29 on x86-64 with v441 (`4ebfa2d047a2`) and v451
(`d9b7226769cc`), which behave the same:

- A `string[10]` set to 50 reads back 50. Filling it with `FillChar`
  changed a neighbouring `Integer` from 777 to 2021161080; the program
  above, built from this page, crashed with a segmentation fault (exit 139)
  and printed nothing.
- A `ShortString` set to 1000 reads back 232, the count's low byte. FPC
  gives 255.

FPC 3.2.2 also lets a `string[10]` grow to 50 and overwrite its neighbour
(the `Integer` read 30840 there), so for `string[N]` this is FPC's behaviour
too. It is listed because the result is memory corruption.

**Workaround:** check the count against the string's capacity first:
`if n > High(t) then n := High(t);`. `High` of a `string[10]` is 10, and of
a `ShortString` 255, with v451 as with FPC.

Wrong in v441 to v451. Fixed after v451 (`5ebf185c24` and `e04f41f9d7`, in
no pin yet): `SetLength` stops at the capacity. On the compiler built at
`e04f41f9d7` (`a91df2b3a1a8`) the program above prints `var 10 777`, and a
count of 50 held in a variable gives 10 for a `string[10]`, 8 for a
`string[8]` record field and 6 for an element of an array of `string[6]`,
each with its neighbour unchanged; a `ShortString` set to 1000, or through
a pointer to 300, gives 255, as in FPC. Two answers differ from FPC on
purpose: a `string[N]` stops at N where FPC overruns it, and a negative
count gives 0 where FPC gives the count's low byte (251 for -5).

### C: `long double` is 8 bytes

GCC's `long double` is 16 bytes on x86-64; PXX's is 8, the same as `double`. A
single program is consistent with itself, but a struct that contains one has a
different size from GCC's: `struct { char c; long double y; }` is 16 bytes here
and 32 under GCC. That matters as soon as such a struct crosses into
GCC-compiled code or into a file format. (Measured with v425, and again on
2026-09-28 with v450 (`c19cc2d531e4`) and the compiler built at `fce510f98d`:
8 and 16 bytes, against GCC's 16 and 32.)

**Workaround:** use `double`, not `long double`, in a struct that GCC-compiled
code or a file format shares.

### riscv32 and Xtensa: arithmetic flushes subnormal doubles to zero

On riscv32 and Xtensa (both ABIs), double arithmetic runs in software
(`compiler/builtin/softfloat.pas`), which flushes subnormal numbers, the
values below about 2.2e-308, to zero. Every operation with a subnormal
operand returns zero (`x * 1.0`, `x + x`, `x - 0.0`, `x / 1.0`), and so does
every result that would be subnormal (`1e-300 * 1e-10`). Comparing, copying
and storing a subnormal are exact. So `if x > 0.0 then y := x * 1.0` can give
a zero `y` for an `x` the same program found to be above zero. Nil Python's
`math.frexp(5e-324)` gives `(0.5, -1086)` there, where CPython gives
`(0.5, -1073)`. This is the documented behaviour of that software arithmetic,
stated in the unit's header, not a crash, and flush-to-zero is a common mode
on small devices. x86-64, i386, arm32, aarch64 and wasm32 use the hardware or
host arithmetic and keep subnormals. Measured on 2026-09-28 with v450
(`c19cc2d531e4`) on x86-64 and under QEMU user mode for the others
(`wasmtime` for wasm32), with a subnormal built from its bit pattern at run
time; the same on riscv32 with v441 (`4ebfa2d047a2`) and with the compiler
built at `fce510f98d` (`f545c8410b32`). The ESP32-C3 and ESP32-S3 use these
two backends, and with v450 the same program gives the same answers as an
ESP-IDF image under Espressif's QEMU on both chips (`tools/esp_run.sh`); it
was not run on a board. **If it matters:**
keep intermediate values above 2.2e-308, for example by working in scaled
units. A value that is already subnormal cannot be scaled back up on these
targets, because the scaling is itself arithmetic on it.

## Stops at run time

- **wasm32: integer division or `mod` by zero stops the module instead of
  raising `EDivByZero`.** `a div b` or `a mod b` with `b` zero at run time
  ends the program with wasmtime's `wasm trap: integer divide by zero` (exit
  134), so an `except on E: EDivByZero` around it never runs and no Runtime
  error 200 is printed. On x86-64 the same program prints `caught
  EDivByZero`, as FPC 3.2.2 does, and without the `try` it stops with
  `Runtime error 200 (division by zero)`. Measured on 2026-09-29 under
  wasmtime 48.0.1 with v450 (`c19cc2d531e4`) and the compiler built at
  `dadc02de44` (`d9b7226769cc`), which behave the same. Wrong in v441 to
  v451. Fixed after v451 (`3a406ba550`, in no pin yet): the compiler built at
  `ff27fe7269` (`18dcf7f85d20`) prints `caught: Division by zero` for a
  `try`/`except on E: EDivByZero` around `7 div ParamCount` under wasmtime,
  where v451 stops the module. **Workaround:** on wasm32, test the divisor
  for zero before dividing.

- **Pascal: `-r` on a record compiles, and the program crashes.** For a
  record `r` with no unary `-` operator, `b := -r` builds, and the program
  stops with a segmentation fault (exit 139) when that line runs, before it
  prints anything. FPC refuses it: "Operator is not overloaded". This
  includes `ucomplex`'s `complex` and `vecmath`'s vectors, whose units
  declare no unary minus. Measured on 2026-09-29 on x86-64 with v441
  (`4ebfa2d047a2`), v451 (`d9b7226769cc`) and the compiler built at
  `9bf9b1c173` (`722c38c6faeb`), which behave the same. Wrong in v441 to
  v451. Fixed after v451 (`f499d25ded`, in no pin yet): the compiler built at
  `f499d25ded` (`81c16b5e3461`) refuses `-r` with FPC's `Operator is not
  overloaded: - "TR"`, and a `vecmath` vector the same way; `ucomplex` now
  declares a unary minus, so `-z` gives the same answer as `cneg(z)`.
  **Workaround:** `cneg(z)` for a complex number, `v * -1.0` for a vector;
  both give the right answer with v451. See
  [Complex numbers, vectors and RTTI](../library/math-and-rtti.md).

### ESP: bare-metal images do not run on a real chip

Images built with `--esp-profile=bare` fault on the first byte access to a
global or a string, and their UART output is lost. Measured on an ESP32-S3 with
v424; a bare ESP32-C3 image has never been run on silicon. They run under
Espressif's QEMU (`qemu-system-xtensa` and `qemu-system-riscv32`), which is what
the bare profile is for. esptool cannot convert a bare ELF either, since it has
no section headers. **Workaround:** on hardware, build the program as an
ESP-IDF component (the default); see [ESP32](../targets/esp32.md).

### Native TLS: most HTTPS sites fail certificate verification

Wrong in v441 to v451. Fixed after v451 (`8d0a99417e`, in no pin yet); see
"After v451" below. TLS 1.2-only servers still fail.

The native TLS 1.3 backend (`tls13_native`, switched on with
`Tls13NativeRegister`) cannot check an ECDSA signature made with SHA-384,
and cannot use a P-384 key. Nearly every public site has one somewhere in
its certificate chain, so for most sites the request fails cleanly: `Ok` is
`False`, and `Tls13NativeLastError` says `certificate chain does not verify
to a trusted root (store /etc/ssl/certs/ca-certificates.crt, 121 roots)`.
It fails closed: no connection is accepted that was not verified.

Measured on 2026-09-29 on x86-64 with v451 (`d9b7226769cc`), from an
unpacked release archive, with `HttpGet('https://<host>/')`:

| host | native backend | OpenSSL backend | chain, from `openssl s_client` |
| --- | --- | --- | --- |
| letsencrypt.org | fails | status 200 | ECDSA with SHA-384, P-384 keys |
| github.com | fails | status 200 | ECDSA with SHA-384 above the leaf |
| codeberg.org | fails | status 200 | ECDSA with SHA-384, P-384 keys |
| www.wikipedia.org | fails | status 403 | ECDSA with SHA-384, P-384 keys |
| cloudflare.com | fails | status 301 | ECDSA with SHA-384 above the leaf |
| example.com | fails | status 200 | ECDSA with SHA-384, P-384 keys |
| www.python.org | status 200 | status 200 | RSA with SHA-256 only |
| docs.espressif.com | fails (TLS 1.2 only) | status 302 | not reached |
| micropython.org | fails (TLS 1.2 only) | status 200 | not reached |

Every host that failed has an ECDSA signature with SHA-384 in its chain,
and the one that worked has none. The 403 and 301 are the sites' own HTTP
answers; the TLS connection succeeded. The compiler built at `c44341534a`
(`81c16b5e3461`) fails in the same way on letsencrypt.org and example.com,
and gets 200 from www.python.org. Of the 121 roots in that store, 35 have a
P-384 key.

The native backend speaks TLS 1.3 only. A server that offers only TLS 1.2
answers its first message with an alert, and the request fails with
`expected a handshake record, got type 21` (21 is a TLS alert). Both
docs.espressif.com and micropython.org did that; `openssl s_client -tls1_3`
got alert 70 (protocol version) and alert 40 (handshake failure) from them.
This is by design for now, not the signature gap above. The signature types `x509` understands are listed on
[Cryptography](../library/crypto.md#checking-signatures-and-certificates-x509-rsa-ed25519).

**Workaround:** on x86-64 (and i386 from v448), use the OpenSSL backend,
`OpenSslTlsRegister` from `tls_openssl`, built with `-dPXX_DYNLIB_LIBC`: it
completed the TLS handshake with all nine hosts above, verifying each
certificate. See
[Networking](../library/networking.md#openssl-backend). A static program
with no C library has no workaround yet.

**After v451** (`8d0a99417e`, in no pin yet), `x509` checks ECDSA with
SHA-384 and SHA-512, keys on P-384, and RSA with SHA-384 and SHA-512.
Measured on 2026-09-29 on x86-64 with the compiler built at `8d0a99417e`
(`553677b94940`, with that tree's library), same program, same nine hosts:
the six that failed now complete the handshake and give the same status as
the OpenSSL backend (200, 200, 200, 403, 301, 200), www.python.org still
gives 200, and docs.espressif.com and micropython.org still fail with
`expected a handshake record, got type 21`, because they speak only TLS
1.2. The v451 build, run in the same minute, still failed on
letsencrypt.org and example.com. Of the 121 roots in the store, 115 now
verify their own signature, against 58 with v451; the six left are five
signed with SHA-1 and one on P-521, which `x509` still refuses.

**Slow on the ESP32-C3.** The fix is correct there but slow. Measured on an
ESP32-C3 board by the fix's author, after v451: one P-384 signature check
takes 22.8 s and one P-256 check 12.1 s, so an HTTPS request to
letsencrypt.org spends about 80 s in the TLS handshake. The ESP32-S3 has
not been measured. See
[Cryptography](../library/crypto.md#checking-signatures-and-certificates-x509-rsa-ed25519).

## Refused, with a message

These do not compile, or compile with a warning. None of them produces a wrong
answer silently. (Measured with v425, and again on 2026-09-29 with v451,
`d9b7226769cc`: the `__thread` warning on riscv32, `setvbuf` returning nonzero
for `_IOFBF` and `_IOLBF` and 0 for `_IONBF` on all five Linux CPUs, and
`--shared` refused on aarch64, arm32 and i386.)

- **C `__thread` on riscv32** compiles with a warning that every thread
  shares one copy. riscv32 has no threads, so no program is affected.
- **C `setvbuf` with full or line buffering** returns nonzero: PXX's C streams
  are unbuffered, and the call says so rather than claiming success.
- **`--shared` on aarch64 and arm32** is refused with
  `shared-library output is x86-64 only`, as on i386.
- **Nil Python: a name bound to a Pascal `array of T` result** can only be
  passed whole to a Pascal array parameter. Everything else on it is refused,
  on purpose, until a conversion to a list exists: `a[1]`, `len(a)`, `for x in
  a`, `print(a)`, `b = a` and `return a` each stop with `"a" holds a Pascal
  dynamic array, which NilPy cannot use as a Python value yet: it can only be
  passed whole to a Pascal array param...`. A def that indexes a
  module-level bound name (`def g(): return a[1]`, before or after the
  binding) is refused too, by the older `Nil Python: annotate the type / too
  dynamic`; passing it whole from a def (`return d.SumO(a)`) prints `60`, as
  intended (x86-64, v450). v449 refused the binding itself
  (see the row under Fixed since v441). A Nil Python list held in a name is
  not accepted by a Pascal array parameter either (`x = [1, 2, 3]` then
  `d.SumO(x)`: `no overload of SumO matches these arguments`). Inside a def,
  `return d.SumV(a)` is refused with `Nil Python: annotate the type / too
  dynamic` by v448, v449 and v450; `t = d.SumV(a)` then `return
  t` prints `60` with v448 and v450. Measured on 2026-09-28 with
  v448 (`b2b325036c3b`), v449 (`0ded1e5d04c8`) and v450 (`c19cc2d531e4`), on x86-64 and on i386 under QEMU user mode,
  with the `dynarr` unit of `test/nilpy_dynarr/`.

## Nil Python

Nil Python is best effort in this beta. It compiles Python-shaped source ahead
of time and is not CPython: CPython compatibility is not a goal of this
release, and it has a real backlog. Its measured list of limits is kept on the
[Nil Python page](../targets/nil-python.md#known-limits), and the deliberate
differences from CPython are recorded beside it. On ESP, the model is
MicroPython's assumptions about a small device, such as math errors not halting
the program. 15 of 16 common MicroPython drivers compile unchanged (measured
with v445); see
[MicroPython](../library/micropython.md).

Found on 2026-09-29, and **open in v441 to v451**:

- **Nil Python: `from X import *` does not compile.** A star import from any
  module, such as `from math import *` or `from os.path import *`, stops the
  build with `expected expression` on that line, where CPython imports the
  module's public names. Measured on 2026-09-29 on x86-64 with v441
  (`4ebfa2d047a2`), v450 (`c19cc2d531e4`) and v451 (`d9b7226769cc`), which
  behave the same. **Workaround:** `import math` and write `math.sqrt(x)`, or
  import the names you use, `from math import sqrt, pi`; with v451 both print
  what CPython prints.

- **Nil Python: `atexit.unregister(f)` does nothing when `f` is a def named
  directly.** After `atexit.register(never)` and `atexit.unregister(never)`,
  `never` still runs when the program ends; CPython does not run it. Measured
  on 2026-09-29 on x86-64 with v441 (`4ebfa2d047a2`), v450 (`c19cc2d531e4`)
  and v451 (`d9b7226769cc`), which behave the same, and with the compiler
  built at `9bf9b1c173` (`722c38c6faeb`). **Workaround:** pass the same variable to both calls
  (`h = never`, `atexit.register(h)`, `atexit.unregister(h)`), or the value
  `register` returned; with v451 both remove it. See
  [System units](../library/system-units.md#atexit-running-code-when-the-program-ends).

Found on 2026-09-28, and **open in v441 to v450** and after it:

- **Nil Python: arithmetic on `None`, or a string minus a large integer, gives
  a number.** `None + 1`, `1 + None`, `None - 1`, `None * 2`, `None + True`,
  `True - None` and `2 ** 70 + None` treat `None` as `0` (`1`, `1`, `-1`, `0`,
  `1`, `1`, `1180591620717411303424`), where CPython raises `TypeError`, so an
  `except TypeError` never runs. A string minus an integer too large for 64
  bits does the same: `"ab" - 2 ** 64` gives `-18446744073709551616`, while
  `"ab" - 5` raises `TypeError` as it should. Valid programs are not
  affected; a program that relies on the error is. Measured on 2026-09-28
  against CPython, with v450 (`c19cc2d531e4`) and the compiler `8d5d0f2653f0`
  (built at `cafc739cbf`) on x86-64 and under QEMU user mode on i386, arm32,
  aarch64, riscv32 and Xtensa (both ABIs), and with v441 (`4ebfa2d047a2`) on
  x86-64, which behave the same.
  **Workaround:** test for `None` (`if x is None:`) before the arithmetic.

- **Nil Python: `hex`, `oct` and `bin` of a `**` result are wrong past 64
  bits.** `hex(2 ** 70)` prints `0x0` and `hex(3 ** 50)` prints
  `0x53f0db2fd09de3c9`, its low 64 bits, where CPython prints
  `0x400000000000000000` and `0x980553f0db2fd09de3c9`; `hex(-2 ** 63)` prints
  `-0x` for CPython's `-0x8000000000000000`. Measured on 2026-09-29 on x86-64
  with v441 (`4ebfa2d047a2`), v450 (`c19cc2d531e4`) and v451
  (`d9b7226769cc`), which behave the same. Wrong in v441 to v451. Fixed after
  v451 (`e375fbfd68`, in no pin yet): the compiler built at `ff27fe7269`
  (`18dcf7f85d20`) prints CPython's three lines. **Workaround:** convert
  through a string first, as in `hex(int(str(2 ** 70)))`: with v451 that
  gives CPython's output for `hex`, `oct` and `bin` in the cases above. Typing the
  variable `int` does not help, and `format(n, "x")` raises `ValueError`.

**Nil Python through `./pxx`: `import time`, `import string` and `import
utime` find the C headers.** The `./pxx` wrapper that `install.sh` writes puts `lib/crtl/include`
on the unit search path, and there Nil Python's `import time` and `import
string` bind the C headers `time.h` and `string.h` instead of PXX's Python
modules. `time.sleep`, `time.sleep_ms`, `time.ticks_ms` and
`string.ascii_lowercase` then fail to compile with `no member sleep came of
the qualifier time` (and the same for the others). `time.time()` still
compiles, because C declares `time()`, and `import math` is not affected.
The same programs compile and run when the compiler is called directly: a
program that is only `import time` and `time.sleep(0.01)` builds that way but
not through `./pxx`. `import utime` fails differently: `print(utime.localtime(31536000))`
stops at compile time with `this build would die at exec: localtime is
imported from libutime.so`, and prints `(1971, 1, 1, 0, 0, 0, 4, 1)` when the
compiler is called directly (v451, 2026-09-29). Measured on 2026-09-29 on x86-64 with the pinned v450
(`c19cc2d531e4`), through a checkout's `./pxx` (written by
`tools/install.sh`, last changed on 2026-09-25) and directly. **Workaround:** call the compiler directly
(`compiler/pxx-<arch>` in the release tarball, the pinned binary in a
checkout) instead of `./pxx` for a Nil Python program that imports `time`,
`string` or `utime`. Wrong in v441 to v451. Fixed after v451 (`ff6115d2d1`,
in no pin yet): through a wrapper that runs the compiler built at
`ff27fe7269` (`18dcf7f85d20`), `time.sleep` compiles, `string.digits` prints
`0123456789` and the `utime` line prints the tuple above.

**Nil Python on the ESP32-C3: `list.sort()` runs out of heap at about half
the list length that can be built.** On a C3 board, in the `nilpy-c3` example
project, a shuffled list of integers can be built up to 4,093 elements (4,125
runs out of memory), but sorting it fits only up to 2,031 (2,062 runs out,
2,078 with v450, whose insertion sort did not finish 2,031 elements within
the 45-second run, but did not run out of memory either). A list of objects with `__lt__` sorts up to 2,037 (2,068
runs out) with both compilers. The limit is the same with v450's insertion
sort and with the merge sort that replaced it, so the sort's own index
scratch space is not what sets it; sorting needs about as much free heap
again as the list itself. The program fails with `pxx: out of memory
(ESP-IDF heap exhausted)`. Measured on 2026-09-28 and 2026-09-29 by booting
one size at a time, with v450 (`c19cc2d531e4`) and the compiler built at
`aefc7ba4bd` (`1634f6483109`); the 4,093 is for the second only. The program,
its recipe and the table are in `test/esp_board_list_sort_ceiling.npy`.
**Workaround:** on a C3, keep a list you sort under about 2,000 elements.

### exec and eval

`exec` and `eval` run Nil Python source at run time, and accept less than the
compiler does. These five rows are where that goes wrong.

**Nil Python: a method reached from `exec` takes the type of its one compiled
call, and a float passed to an integer parameter is silently truncated.** When
every compiled call of a method passes the same kind of value to a parameter
with no annotation, the compiler gives that parameter the type (`def mi(self,
x)` called only as `n.mi(3)` makes `x` an integer). That is deliberate and
makes such calls fast. A call from source compiled at run time, such as
`exec("def __body__():\n    n.mi(2.7)\n", env, ns)`, cannot be seen at
compile time, so its argument is converted to that type rather than passed as
is. One of the three results is a wrong answer with no message: a float into
an integer parameter is truncated (`n.mi(2.7)` gets `2`, CPython `2.7`). The
other two are by design: a string into that parameter raises `TypeError`
(CPython passes `'ab'`), and an integer into a float parameter arrives as `3.0`
(CPython `3`), which loses nothing. A parameter whose compiled calls pass
different kinds of value is not given a type, and behaves as in CPython.
Measured on 2026-09-29 with v450 (`c19cc2d531e4`) and the compiler built at
`6dcfbbb0e0` (`9ce84ba69527`) on x86-64, and with the latter under QEMU user
mode on i386, arm32, aarch64 and riscv32, which print the same.
**Workaround:** annotate a parameter that `exec` code will call as `x:
object` (or `Any`). That keeps the compiler from giving it a type, so all
three calls print what CPython prints (x86-64, `9ce84ba69527`). A scalar
annotation such as `x: float` gives it a type by hand: it stops the
truncation, but a string still raises `TypeError`. Re-measured on 2026-09-29
with the compiler built at `f499d25ded` (`81c16b5e3461`) on x86-64 and aarch64:
the same as v451, and the `object` annotation still works.

**Nil Python: `exec` publishes a def only when it is named `__body__`.**
After `exec("def f():\n    return 42\n", {}, ns)`, `ns` is empty, and
`ns["f"]` raises `KeyError: 'f'`. The message names your key, so it reads as
a wrong lookup, while the cause is that `exec` did not store the def. Only a
def named `__body__` lands in `ns`; `helper`, `f` and `__b__` do not. A
variable assigned at the top of the executed source is stored:
`exec("def helper(x):\n    return x + 1\nresult = helper(41)\n", {}, ns)`
gives `ns["result"] == 42`. **Workaround:** name the def `__body__`, or
assign the value you need to a variable in the executed source. Measured on
2026-09-29 on x86-64 with v450 (`c19cc2d531e4`) and the compiler built at
`1763b6232b` (`70e57d59b777`), which behave the same.

**Nil Python on i386, arm32 and riscv32: `exec` code calling a method with
annotated parameters passes wrong values.** With `def greet(self, name: str,
n: int, flag: bool)`, the call `p.greet('x', 3, True)` made from source run by
`exec` prints `hi  12884901888 True` on i386 (an empty string, and 3 moved up
32 bits) and `hi x 12884901888 False` on arm32 and riscv32, with no message;
x86-64 and aarch64 print `hi x 3 True`, as CPython does. A parameter without
an annotation is affected the same way once the compiler has given it a type
from its compiled calls (see the row above on a method reached from `exec`):
after `p.plain("y", 4, False)` in the program, the `exec` call prints `hi
12884901888 True` on i386 and stops with SIGSEGV on arm32. Without any
compiled call, or annotated as `object`, it gets the right values. Measured on
2026-09-29 with v450 (`c19cc2d531e4`) and v451 (`d9b7226769cc`), which behave
the same, under QEMU user mode. Wrong in v441 to v451. Fixed after v451
(`191239f538`, in no pin yet): with the compiler built at `f499d25ded`
(`81c16b5e3461`), on i386, arm32 and riscv32, such a call raises a
`TypeError` that the caller can catch (`reflected call to greet is refused:
parameter 1 ... is not 64-bit, so the arguments would be misaligned ...`)
instead of passing wrong values, for the annotated method and for the
unannotated one alike; x86-64 and aarch64 still print `hi x 3 True`.
**Workaround:** on a 32-bit target, annotate the parameters of a method that
`exec` code calls as `object` (`name: object, n: object, flag: object`);
measured on i386, arm32 and riscv32 with v451, and with the compiler built at
`f499d25ded`, where it gives the right values too.

**Nil Python: the parameters of an `exec`'d `__body__` read `None`.** A
`__body__` defined by `exec` and called from the program does not receive its
arguments: every parameter reads `None`, with no message. After
`exec("def __body__(s):\n    return s\n", {}, ns)`, `ns["__body__"]("ab")`
returns `None` (CPython `'ab'`); with two parameters, `[a, b]` is
`[None, None]` for `(1, "x")`; `n + 1` gives `1` for `41` (CPython `42`); and
`int(s)` gives `0` for `"ab"` instead of raising `ValueError`. A def nested
inside `__body__` and returned from it does receive its argument. Measured on
2026-09-29 on x86-64 with v450 (`c19cc2d531e4`) and the compiler built at
`1763b6232b` (`70e57d59b777`), which behave the same. **Workaround:** give
`__body__` no parameters and return a nested def that takes them, or pass
values in through a variable in the `exec` globals.

**Nil Python: `raise` inside `exec`'d code stops the program, while a
builtin's error there can be caught.** `raise ValueError('bad')` in source run
by `exec` prints `pyeval: ValueError: bad` on standard output and exits with
status 1; an `except ValueError` around the call never runs. That `raise` is
not yet catchable there is by design for now: making it catchable is a later
step, as the comment on the `raise` handler in `compiler/builtin/pyeval.pas`
says. A `try` inside the executed source is not accepted either (`pyeval:
unexpected token in expression: ":"`). An error that a builtin raises is an
ordinary exception, and the caller's `except` catches it: `int('ab')` gives
`ValueError` in a `__body__` and in a def nested in it, and `[1][5]` gives
`IndexError` in a `__body__`. Measured on 2026-09-29 on x86-64 with v450 (`c19cc2d531e4`) and
the compiler built at `1763b6232b` (`70e57d59b777`), which behave the same.
**Workaround:** test the condition in the executed code with an `if` and
return a value the caller checks (such as `-1`), instead of raising.

## Memory leaks

Three limits are open; the leaks fixed before and after the release are listed under [History](#history).

Program-level global variables are not finalized when the program exits. This
is a one-time cost at exit, not a leak that grows while the program runs.

Nil Python: a string temporary built by a module-level statement, such as
`print("n=" + str(n))` outside any function, is kept until that statement runs
again. That is at most one string per source line, and a loop reuses it, so
the cost is bounded by the program's length and does not grow while it runs.
Inside a function, temporaries are released when the statement ends.

**Nil Python: a reference cycle is never freed.** Nil Python frees an object
when its last reference goes away; there is no garbage collector to find
objects that only refer to each other. That is the design for this beta, and
it differs from CPython and MicroPython, which both reclaim cycles. A function
that makes two objects point at each other (`a.other = b; b.other = a`) keeps
both after it returns: 2 objects kept after one call, 10 after five, measured
with v445 and with the compiler at `ae11f1ddb5`. **Workaround:** break the
cycle before letting go (`b.other = None`); measured, that keeps none.

## ESP networking

**TLS on ESP is client-only, and does not check certificates by default.**
`ssl.wrap_socket` and `SSLContext` work, so `urequests.get("https://...")` and
`MQTTClient(..., ssl=True)` do too, but, as in MicroPython, the server's
certificate is only checked when the program asks for `CERT_REQUIRED` and
passes the authority it trusts; there are none on the chip. See
[TLS on ESP](../library/esp.md#tls). A Nil Python program on a desktop has no
`ssl` module, so `urequests` there refuses `https://` URLs with a `ValueError`;
desktop Pascal programs have TLS through the `http` unit.

## Optimisation levels

`-O2` is the default and the level the compiler proves on itself. `-O3` is
experimental: its differential check against `-O2` had two failing shards at
v439. Use `-O3` only if you check the output.

**Workaround:** use `-O2`, the default.

## By design: `Trunc` of an out-of-range float into a 32-bit integer

`Trunc(1e30)` stored in an `Int64` saturates to 9223372036854775807. Stored in
a `LongInt` it gives -1, the low 32 bits of that saturated value. This is the
same on every target, desktop and ESP (measured with v425; the desktop half
again with v451 on x86-64, i386, aarch64, arm32 and riscv32). A float that does
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
| Nil Python: `//` and `%` by zero | runtime error 200, which `except` cannot catch, when the divisor is only known at run time; `ZeroDivisionError` when the compiler can see it is zero or the def is typed (measured with v450; this may change before 1.0, so test the divisor if a program depends on either behaviour) | gives 0, the program continues |
| Nil Python: float `/` by zero | `ZeroDivisionError`, as in CPython | Inf |

Each cell was measured on v425. The desktop column was measured again on
2026-09-29 with v451 (`d9b7226769cc`) on x86-64, i386, aarch64, arm32 and
riscv32 Linux, for Pascal, C and Nil Python, and every cell held. The ESP
column was measured under Espressif's QEMU on both chips, for Pascal, C and
Nil Python; its Pascal and C integer cell again with v450 (see
[Numbers on ESP](../library/esp.md#numbers-on-esp)). wasm32 is not in the
desktop column: there an integer division by zero stops the module (see
"Stops at run time" above). This is not a bug to be fixed: if you need a zero divisor to stop an ESP program,
test the divisor yourself.

## Reporting a problem

[Reporting bugs](./reporting-bugs.md) says what to put in a report, how to
name the compiler you ran (from a checkout or a release archive), and how to
cut a program down to a small reproducer. A program that compiles and gives a
wrong answer is the most useful report you can send.

## History

What was wrong in an earlier pin and is fixed, and the measurements behind the open rows above.

### Fixed since v441

These are wrong in v441 and fixed in a later pin or after the latest one, as
each row says: "wrong in v441 to v446" means v446 is the last pin with the
fault; the fix landed after it, so the source of every later pin carries it. The C rows were checked against GCC's output and the Pascal rows
against FPC 3.2.2. The Nil Python rows were checked against CPython 3 and say
what they were measured with.

Pin v448's own binary (`b2b325036c3b`) was graded on the native test tier
on 2026-09-28 at `7abbe26f4e`, with no skipped or flaky rows. One row is
still red: `test/c_crtl_wait.c`, where riscv32 under QEMU 8.2.2 leaves
`wait4`'s rusage untouched; whether PXX or the emulator is at fault is not
yet known.
`-O3` was not part of that run.

- **Standard error went to standard output on every target but x86-64.** On
  i386, arm32, aarch64, riscv32 and Xtensa (both ABIs), Pascal's
  `WriteLn(StdErr, ...)` and `Write(StdErr, ...)` and Nil Python's `print(...,
  file=sys.stderr)` wrote to standard output. On x86-64, `WriteLn(StdErr,
  1.5:0:1)` wrote `1.5` to standard output and only the line end to standard
  error. `WriteLn(StdErr)` alone was refused on every target with `expected
  expression`; FPC 3.2.2 accepts it. Wrong in v441 to v450. Fixed after v450
  (`f3343ccecc`, in v451). Measured on 2026-09-28 on x86-64 and under
  QEMU user mode on i386, arm32, aarch64, riscv32 and Xtensa (both ABIs), with
  v450 (`c19cc2d531e4`) and the compiler built at `fce510f98d`
  (`f545c8410b32`): `test/test_stderr_separation.pas` and
  `test/test_nilpy_print_to_stderr.py` match their `.expected` and
  `.err.expected` on all seven targets with that compiler, and so do strings,
  integers, a formatted real, mixed `Write`/`WriteLn` and the bare
  `WriteLn(StdErr)`; v450 wrote them to standard output, or refused the bare
  form. The ESP targets build with the fix; ESP output was not checked on a
  board. **On v450 and earlier:** open standard error as a file (`Assign(f,
  '/dev/stderr'); Rewrite(f); WriteLn(f, ...)`) in Pascal, or use
  `sys.stderr.write(...)` in Nil Python; both reach standard error on all
  seven targets with v450.

- **wasm32: no unit's initialization section ran, so `WriteLn(Output, ...)`
  stopped with Runtime error 9.** On wasm32 a program ran its main body but
  skipped every unit's `initialization`. With a `Text` variable declared,
  `WriteLn(Output, ...)` and `WriteLn(StdErr, ...)` stopped with `Runtime
  error 9 (I/O error)` and printed nothing, and SysUtils' `LongMonthNames[1]`
  was empty. Wrong in v441 to v450. Fixed in v451 (`9de858f83d`). Measured on 2026-09-29 under wasmtime 48.0.1: with v441
  (`4ebfa2d047a2`) and v450 (`c19cc2d531e4`) those writes exit 9, and v450
  prints an empty month name; with the compiler built at `dadc02de44`
  (`d9b7226769cc`) they print, and the month name is `January`.

- **Nil Python: a float against a large integer.** `0.0 == 2 ** 64`, `2 ** 64
  == 1.5` and `2 ** 64 != 1.5` stopped the program with `Runtime error 219`;
  `<`, `<=`, `>` and `>=` were right. On the same paths, two answers were
  silently wrong: `x <= nan` and `x >= nan` were `True` for a NaN held in a
  value that may be another type (CPython: `False`), and an integer beyond
  2^53 was compared with a float through a double, so `2 ** 53 + 1 == 2.0 **
  53` was `True`. Wrong in v450 and earlier (the Runtime error also with v441,
  on x86-64). Fixed after v450 (`cafc739cbf`, in v451). Measured on
  2026-09-28 against CPython, on x86-64 and under QEMU user mode on i386,
  arm32, aarch64, riscv32 and Xtensa (both ABIs), with v450 (`c19cc2d531e4`)
  and the compiler built at `cafc739cbf` (`8d5d0f2653f0`): v450 stops or gives
  the wrong answer on all seven, and that compiler matches CPython on all
  seven. **On v450 and earlier:** convert one side first, as in `float(n) ==
  x`, and test for NaN with `math.isnan`.

- **Nil Python: a def passed to a Pascal procedure parameter was never
  called.** With a Pascal `procedure(a: Integer)` type as the parameter,
  `c.CallPr(show, 5)` ran without calling `show` at all: nothing printed, and
  the call returned as if the procedure had done nothing. A def passed to a
  `function` type was called. Wrong in v441 to v450. Fixed after v450
  (`956cba6006`, in v451). Measured on 2026-09-28 on x86-64 and under
  QEMU user mode on i386, arm32, aarch64, riscv32 and Xtensa (both ABIs), with
  v450 (`c19cc2d531e4`) and the compiler built at `52e61383a5`
  (`8d5d0f2653f0`), and on x86-64 with v441 (`4ebfa2d047a2`), v448 and v449: a
  def that prints is called twice with the fix and never before it, and
  `test/test_nilpy_a_def_into_a_procedure_slot_is_called.npy` matches its
  `.expected` on all seven targets with that compiler. **On v450 and
  earlier:** give the Pascal side a `function` type and ignore its result.

- **Nil Python: a def with the name of a Pascal unit's global stopped the
  program.** Pascal names ignore case, so a def `acc` in a program that
  imports a unit declaring `var Acc` (`import 'cbproc.pas' as c`) read the
  unit's variable wherever the def was used as a value: `c.CallI(acc, 5)` and
  `x = acc` then `x(4)` stopped with `Runtime error 216 (nil reference)`.
  Wrong in v441 to v450. Fixed after v450 (`956cba6006`, in v451).
  Measured on 2026-09-28 on x86-64 and under QEMU user mode on i386, arm32,
  aarch64, riscv32 and Xtensa (both ABIs), with v450 (`c19cc2d531e4`) and the
  compiler built at `52e61383a5` (`8d5d0f2653f0`), and on x86-64 with v441
  (`4ebfa2d047a2`), v448 and v449: both print the def's results with the fix
  and stop before it. **On v450 and earlier:** name the def so it matches no
  global of an imported unit, in any case.

- **Nil Python: `None` tests on every backend but x86-64.** On i386, arm32,
  aarch64, riscv32 and Xtensa (both ABIs), `x == None` was `True` and `x !=
  None` `False` when `x` was `0`, `0.0` or `False`, whether a plain variable,
  a list element or a value that may be `None`; an empty string compared
  correctly. On the same backends, a function declared to return a class (`->
  Optional[Word]`) that returned `None`, with its result passed through a
  conditional expression (`w = vm.lookup(name) if isinstance(name, str) else
  None`), gave `w is None` `False`, so an `if w is not None:` guard was
  entered with no object; `bd6edb9f08` had fixed that on x86-64 only. Assigned
  directly, and in every other shape measured, `is None` was right. Wrong in
  v441 to v450. Fixed after v450 (`24038529ba`, in v451). Measured on
  2026-09-28 on x86-64 and under QEMU user mode for the others, with v450
  (`c19cc2d531e4`) and the compiler built at `52e61383a5` (`8d5d0f2653f0`):
  `test/test_nilpy_conditional_expression_none.npy` and
  `test/test_nilpy_none_is_none_on_every_backend.npy` match their `.expected`
  on all seven with that compiler, and differ on the six non-x86-64 targets
  with v450, as does a probe of `== None` on `0`, `0.0` and `False` against
  CPython; v441, v448 and v449 gave the same wrong answers on i386. The
  ESP32-C3 and ESP32-S3 use the riscv32 and Xtensa backends; not run on a
  board. **On v450 and earlier:** test for `None` with `is None` or `is not
  None`, never with `==` or `!=`, and assign an `Optional` class result
  directly before testing it.

- **Pascal: comparing a LongWord with a signed value on 32-bit targets.** On
  i386, arm32 and riscv32, `c > i` with `c: LongWord = 3000000000` and
  `i: LongInt = -1` answered FALSE, and `$FFFFFFFF = -1` answered TRUE. A
  QWord compared with an Int64 was compared unsigned there. Pascal compares
  these as Int64, and each row now matches FPC 3.2.2 on all five targets.
  Wrong in v441 to v446.

- **Pascal: `q in [...]` with a set item beyond 32 bits on 32-bit targets.**
  On i386, arm32 and riscv32, `1 in [4294967297]` answered TRUE and
  `4294967297 in [4294967297]` answered FALSE. They now answer as on x86-64.
  FPC rejects such items, and pxx warns about them. Wrong in v441 to v446.

- **wasm32: Pascal memory leaks that grew with every call.** A function
  returning a record with managed fields (strings, interfaces) leaked the old
  value of the variable it was assigned to, so the loops in
  `test/test_interface_result_temp_leaks.pas` and
  `test/test_case_arm_temp_finalize.pas` grew by 0.5 to 0.9 blocks per trip.
  `Copy` of a string literal or of a shared string leaked one block per call.
  Every string constant was copied to the heap, so a program using `pylib`
  kept about 250 blocks alive at exit. Measured with pin v446 (wasmtime,
  `-dPXX_ALLOC_CENSUS`). Wrong in v446.

- **Nil Python on i386 and arm32: values that differed from x86-64.** Found by
  building the Nil Python test corpus for i386, aarch64 and arm32 at `-O2` and
  comparing each output with x86-64 and CPython. Now the same on every target:
  - `next(g)` and `list(g)` on a generator gave nothing or garbage on i386;
  - `"%x" % -2**63` and `format(v, "o")` raised on i386 and arm32;
  - a def called through a variable (`f = q; f(1)`) lost its default
    arguments, and one with `*args` crashed;
  - on arm32, `int(3000000000.7)`, `round` and `math.floor` of a float past
    2^31 stopped at 2147483647, and `round(7)` printed a huge number;
  - on arm32, a def stored in an object field could not be called back;
  - a method reached by dynamic dispatch or `exec` could return `True` where
    it computed `False`, and `len()` of an `array.array` could be wrong;
  - on i386, an object's default repr could show a negative address.

  `test/test_nilpy_cross32_values.py` fails with pin v446, and so do the
  corpus tests for `round`, `len` of a shim, dynamic dispatch, `exec` returns
  and object repr, each on the target named above. Wrong in v446.

- **Generators: float values, argument slots, and a string literal.** A
  `generator; stackless;` routine received a `Double` parameter as its bit
  pattern (`4612811918334230528.00` for 2.5), lost the fraction of a float
  local kept across a `yield`, and yielded floats wrongly. A generator called
  after another generator was declared got its arguments in the wrong places
  (`1 3 0` for `1 2 3`), silently. A Nil Python generator called with a string
  literal, `for x in gen("hi")`, crashed. This was on every target. See
  `test/test_stackless_float_param_and_element.pas` and
  `test/test_stackless_generator_called_after_a_later_generator.pas`. Wrong in
  v446.

- **wasm32: `Move(s[i], ...)` on a shared `const` string could change another
  variable.** It unshared the string by mistake, and a later write to one
  copy showed in the other. `Copy` does this internally. Matches FPC 3.2.2
  now. Wrong in v446.

- **riscv32: assigning to a `var s: string[N]` parameter did not reach the
  caller.** The caller kept its old value. Wrong in v441 to v446.

- **arm32: a Pascal callback called from C could crash the C caller.** A
  routine passed to libc's `qsort` returned with the registers the ARM ABI
  says it must preserve (r4 to r10) overwritten. Sorting 3 or more elements
  segfaulted inside qsort. Wrong in v441 to v446.

- **Pascal: `Int64(@r.f)` had a garbage high word on 32-bit targets.** For
  an Int64, QWord or Double field, `Int64(@r.i) - Int64(@r)` answered
  4294967297 instead of the field's offset on i386, arm32 and riscv32. It now
  matches FPC 3.2.2. Wrong in v441 to v446.

- **Pascal: `Call(@obj.Method)` crashed on 32-bit targets.** Passing a method
  reference directly to an `of object` parameter segfaulted on i386, arm32 and
  riscv32. Passing it through a variable worked. Wrong in v441 to v446.

- **Pascal: a `static` class method was handed an extra argument.** A class
  property whose accessor is `static`, and a static method called bare inside
  `with`, got the receiver as a first argument. On riscv32 the setter stored
  the class pointer instead of the value. i386, aarch64 and arm32 refused to
  compile the call. Wrong in v441 to v446.

- **Pascal: a cast of untyped memory read at the wrong width.** `Int64(p^)`
  over a plain `Pointer`, or `Int64(v)` for an untyped `const v`/`var v`
  parameter, read 4 bytes on i386, arm32 and riscv32. `Double(p^)` and
  `Single(p^)` converted the bytes' integer value to a float instead of reading
  them as one, on every target. A cast now reads the memory at the cast type's
  width, as FPC does, and each row matches FPC 3.2.2 on all five targets. Wrong
  in v441 to v446.

- **Pascal: `^[i]` on a property's result read the wrong element.** For
  `property L: PIntArray read GetL`, `c.L^[1]` stepped 8 bytes per element
  whatever the element type. It read element 2 of an Integer array, 0 from a
  Word array, and wrote the wrong element too. TList's `list.List^[i]` was
  wrong the same way on i386, arm32 and riscv32. Now each matches FPC 3.2.2 on
  all five targets. Wrong in v441 to v445.

- **Pascal: a helper's members were unreachable inside `with`.** In
  `with c do WriteLn(Two)`, where `Two` is declared by a class helper or a
  record helper for `c`'s type, `Two` was "undefined variable". Two related
  errors also appeared without `with`:
  - A class helper's property was "no such member".
  - A helper for a base class lost to the base class's own method when called
    on a derived object: `d.Own` called `TBase.Own`, where FPC calls the
    helper's.

  Now each matches FPC 3.2.2, in objfpc and delphi mode. Wrong in v441 to
  v445.

- **The compiler could overwrite its own source file.** `pxx g.pas ./g.pas`,
  the absolute path to `g.pas`, `a/../g.pas`, or a symlink to it as the
  output wrote the program over `g.pas`. Naming a used unit or an included C
  header as the output did the same. Only `pxx g.pas g.pas` was caught. Now
  any output that is the same file as an input of the compile is refused, and
  the input is left untouched. Wrong in v441 to v445.

- **C: an initialised `__thread` variable read 0 in other threads.**
  `__thread int tl = 7;` read 7 in `main` and 0 in a thread started with
  `pthread_create`, and in that thread's own threads. Now every thread starts
  at the initialiser, on x86-64, i386, aarch64 and arm32 (checked against
  GCC; riscv32 has no threads). Wrong in v441 to v445.

- **C: a function returning a pointer to an array stepped it one element at a
  time.** For `vec4 *f(void)`, `mat4 *f(void)` or `int (*f(void))[4]`,
  `sizeof *f()` was the element (4, GCC 16 or 64), `f() + 1` stepped one
  element, and `(*f())[i]` and `f()[0][i][j]` read the wrong one. Now each
  matches GCC. Found alongside it: `typedef struct P PA[3];` (the `struct`
  keyword spelling) was one struct, not three (`sizeof(PA)` 8, GCC 24). Wrong
  in v441 to v445.

- **C on i386, aarch64, arm32 and riscv32: values that were right only on
  x86-64.** Each was wrong in v441 to v445 and now matches GCC on all five
  targets:
  - `sizeof` arithmetic had the wrong type for the target. On 32-bit targets
    `-1 < sizeof(int)` was 1 and `i / sizeof(int)` divided signed. On 64-bit
    targets `sizeof a - sizeof b` wrapped at 2^32.
  - A `double` or `float` used as a condition (`if`, `while`, `for`, `?:`)
    tested its bits: `-0.0` was true, and on i386 and arm32 `0.5` was false.
  - On arm32 and riscv32, `va_arg` in a function with many named parameters
    read the named ones again.
  - `CHAR_MIN` and `CHAR_MAX` were -128 and 127 where `char` is unsigned
    (aarch64, arm32, riscv32). `-1 < UCHAR_MAX` was 0.
  - `fesetround` reported success and changed nothing. Now it takes effect on
    i386, aarch64 and arm32. On riscv32, whose doubles are software floating
    point, it refuses any mode but round-to-nearest.

- **i386: `__thread` was one copy shared by every thread, and `threadvar` was
  refused.** A C `__thread` variable, and `errno` through it, read and wrote
  another thread's value (with a compile-time warning); Pascal `threadvar` did
  not compile. i386 now gives each thread its own block, as x86-64 does, also
  when libc is linked. Wrong in v441 to v445.

- **C: an array typedef of structs was not modelled.** With `typedef struct {
  int a, b; } P; typedef P PA[2];`, a struct member `PA ps;` was laid out as
  one `P` (`struct { char c; PA ps; int after; }` 16 bytes, GCC 24), and a
  local `PA x;` was refused at `x[1].b`. Wrong in v441 to v445; fixed in
  `47f3bbccd4`.
- **C: the address of an array or of a row pointed at one element.** `&a + 1`
  stepped one byte for any `a` (GCC: `sizeof a`), `sizeof *&a` answered the
  element, `(&m[0])[1][1]` read the wrong element, and a file-scope
  `int (*r)[3] = &g[1];` was left null. Wrong in v441 to v445; fixed in
  `47f3bbccd4`.
- **C: `sizeof` of a parenthesised row or dereference** (`sizeof((m[0]))`,
  `sizeof(*(p))` for `int (*p)[4]`) answered the size of a pointer. The
  dereference form is fixed in v445 (`84b57aa495`), the row form after it
  (`47f3bbccd4`).

- **C: a struct or union member typed by an array typedef was too small.**
  `struct U { arr3 a; int after; }` with `typedef int arr3[3]` was 8 bytes
  (GCC 16), and writing `u.a[1]` overwrote `u.after`; `struct { int k; mat4 m;
  vec4 v; }` was 12 bytes (GCC 84). Wrong in v441 and v443; fixed in v444
  (`f713506115`). cglm's `mat2x3s`
  union crashed on it; cglm's whole test suite now passes, 1131 of 1131.
- **C: a struct member pointing at an array typedef** (`mat4 *p;`,
  `mat4 *m[3];`) did not know its pointee's shape: `sizeof *s.p` was 4 (GCC
  64) and `(*s.m[0])[1][1]` crashed. Wrong in v441 and v443; fixed in v444
  (`f713506115`).
- **C: an array of pointers to an array typedef** (`mat4 *m[] = {&a, &b,
  &c}`, cglm's `glm_mat4_mulN`) had the wrong size (`sizeof m` 128, GCC 24),
  and `*m[i]` loaded where C decays. Fixed in v443 (`c5ad9480c4`).
- **C: a local with an unsized first dimension of rows** (`vec4 v[] =
  {...}`, `float a[][4] = {...}`) was allocated one row, and the rest of its
  initialiser overwrote neighbouring locals. Fixed in v443.

- **Threads on i386, aarch64 and arm32 shared glibc's thread pointer.** A
  thread started by PXX in a program that links libc used the main thread's
  glibc state, so two threads using `malloc` at once could abort the program
  (the fix's commit measured an abort in 1 of 3 runs on i386, 2 of 3 on
  aarch64, 3 of 3 on arm32, under QEMU). The compiler warned about it. It is
  intermittent: on 2026-09-28, three runs of the same test built with v445
  survived on each of those targets. Each
  thread now gets its own, as on x86-64. Wrong in v441 to v445; fixed in
  v446 (`0ed2b7f6e1`).

- **Pascal and Nil Python: a Pascal result borrowed from a field or global
  was freed under its owner.** A Pascal function returning an object held in
  a field, an array element or a global handed it over as if it were new, and
  the caller's release freed it. In Nil Python, `p = re.compile("a+")` in a
  function called three times answered `True`, then `False` (with
  `-dPXX_HEAP_DEBUG`: "RELEASE of a FREED object") with v445, and `True`
  three times with v446. Wrong in v441 to v445; fixed in v446
  (`601abeecec`).

- **Nil Python: a method called on an attribute or a call result.**
  `r.text.split(":")[0]` and `r.text[0]` worked, but `R().name.upper()`
  stopped with `TypeError: object is not callable` with v445. With v446 the
  three print `ab XY a`, as CPython does. Wrong in v441 to v445; fixed in
  v446 (`d58437f7f6`).

- **Nil Python: `re.findall` stopped at 4096 matches, silently.**
  `len(re.findall("a", "a" * 5000))` answered 4096, and so did a 4,500-match
  `"ab"` search; CPython answers 5000 and 4500. Measured on 2026-09-28: 4096
  with pin v447 (`fad87004e4e8`) and its library, on x86-64; 5000 and 4500
  with pin v448 (`b2b325036c3b`) and its library, on x86-64, i386, aarch64
  and arm32 (QEMU user mode). Wrong in v441 to v447 (`2c3302f96e`).

- **Nil Python: `re` asked for about 800 KB per call.** One `re.compile("a")`
  and a `findall` allocated 820,384 bytes in all with pin v447 and 5,432 with
  pin v448, on x86-64 (`tools/census_at_exit.sh`, 2026-09-28). On an
  ESP32-C3 that was fatal: under QEMU, a program that compiles a pattern
  printed `pxx: out of memory (ESP-IDF heap exhausted)` and rebooted in a loop
  with v447, before its first line of output. With v448 the same program
  (one `re.compile("a")`, then 20 of `re.compile("a+")` with a `findall`
  each) printed its results and ended; free heap was 1,140 bytes lower after
  the 20 compiles. On x86-64, 20 and 80 such compiles both leave 6 blocks
  live at exit, so it does not grow per call. Measured under QEMU, not on a
  board. Wrong in v441 to v447 (`2c3302f96e`).

- **ESP32-S3: `import re` did not compile.** Any Nil Python program that
  imports `re`, built for the S3's windowed Xtensa ABI as the S3 demos are,
  stopped with `target xtensa windowed: aggregate-result frame offset out of
  range` in `lib/rtl/regex.pas`. With pin v448 the same program builds
  (`--target=xtensa --xtensa-abi=windowed --xtensa-long-calls`), and so does
  the classic ESP32 build (`--target=esp32`), on 2026-09-28. On a physical
  ESP32-S3 with the v448 binary, `compile`, `search`, `match`, `findall`,
  `sub`/`subn`, `split`, `fullmatch`, `IGNORECASE`, `finditer` and the
  pattern cache printed CPython's answers, and a 2,000-iteration heap soak
  stayed flat at 84 to 88 bytes against a control that kept 647 bytes per
  result (one boot; recorded in `devdocs/progress/LOGBOOK.md` by
  `19f4728e10`). Wrong in v441 to v447 (`1c2fb47dd8`). The call0 ABI
  builds since v449; see the call0 row below.

- **Nil Python: `m.start()` and `m.end()` with no argument did not compile.**
  CPython reads them as group 0: `re.search("b+", "abbbc")` gives `1 4`.
  pxx stopped with `start() requires 1 argument(s), none given`. Measured on
  2026-09-28 with pin v448 on x86-64. Wrong in v441 to v448. Fixed in v449
  (`19f4728e10`): measured again on 2026-09-28 on x86-64, v448
  (`b2b325036c3b`) refuses it and v449 (`0ded1e5d04c8`) and v450
  (`c19cc2d531e4`) print `1 4`, as CPython does. **On v448:** write
  `m.start(0)` and `m.end(0)`.

- **Nil Python: a Pascal `array of T` result bound to a name read the wrong
  values.** With a Pascal unit imported as `d` whose `MakeArr(4)` returns `0,
  10, 20, 30` as an `array of Integer`, `a = d.MakeArr(4)` then `print(a[3])`
  printed `0`, `for x in d.MakeArr(3):` stopped with `TypeError: expected a
  str, a list or a dict, got int`, and `len()` of it did not compile. After
  v448 (`9bd7f662e5`, in v449) binding it to a name, `len()` and `for` are
  refused at compile time, and the message says to index the call directly.
  `d.MakeArr(4)[3]` prints `30` with every compiler measured. One shape that
  worked is now refused too: `a = d.MakeArr(4)` then `d.SumArr(a)`, a Pascal
  routine taking the array, printed `60`. Passing the call straight in,
  `d.SumArr(d.MakeArr(4))`, compiles with none of them (`by-reference argument
  must be a variable`), whether the parameter is `const`, by value, `var` or
  an open array. Measured on 2026-09-28 on x86-64 with v441 (`4ebfa2d047a2`),
  v448 (`b2b325036c3b`) and the compiler built at `a2614fcb8b`
  (`5dea028059af`); `d.MakeArr(4)[3]` also prints `30` on i386 with that
  compiler. **On v448:** index the call directly, and leave work on the whole
  array to Pascal.

- **Nil Python: a Pascal `array of T` result could not be passed straight to a
  Pascal array parameter.** `d.SumV(d.MakeArr(4))`, where `SumV` takes the
  array by value, was refused with `by-reference argument must be a variable`,
  and so were a `const` parameter (`SumC`) and an open array (`SumO`). Fixed
  in v450 (`63c957f093`). Measured again on 2026-09-28 with the pinned
  binaries, each in its own tree: v449 (`0ded1e5d04c8`) and v450
  (`c19cc2d531e4`), on x86-64 and i386 with the current `dynarr` unit: v449
  refuses `d.SumV(d.MakeArr(4))` with that message, and v450 prints `60` for
  all three, at module level and inside a def. First measured on 2026-09-28 with
  v449 (`0ded1e5d04c8`) and with the compiler built at `f53fd89ef0`
  (`2dd7329329c8`), on x86-64 and on i386 under QEMU user mode, with the
  `dynarr` unit of `test/nilpy_dynarr/`: v449 refuses all three, at module
  level and inside a def; with that compiler `print(d.SumV(d.MakeArr(4)),
  d.SumO(d.MakeArr(4)), d.SumC(d.MakeArr(5)))` prints `60 60 100` in both
  places, which is what FPC 3.2.2 prints for the same calls in Pascal. The
  fixture
  `test/test_nilpy_a_dynamic_array_result_passed_to_pascal_is_released.npy`
  (2000 trips, two arrays each) ends with `live=3` in the allocation census.
  **On v449:** leave the call to Pascal: a Pascal routine that returns
  `SumV(MakeArr(n))`, called from Nil Python as `w.SumOfMake(4)`, prints `60`
  with v449.

- **Nil Python on v449: a Pascal `array of T` result bound to a name could not
  be passed to Pascal.** `a = d.MakeArr(4)`, then `d.SumV(a)`, `d.SumO(a)` or
  `d.SumC(a)`, printed `60` each with v448, at module level and inside a def,
  on x86-64 and i386. v449 refuses the binding with `"MakeArr" returns a
  Pascal dynamic array, which NilPy cannot use as a Python value yet`. Fixed
  in v450 (`a49f6f12c6`): v450 prints `60` for all three again, in both places
  and on both targets, and a def that reads a module-level bound name (`def
  f(): return d.SumO(a)`) prints `60` too. A census over 2000 trips binding
  two arrays each ends with `live=3`. Measured on 2026-09-28 with v448
  (`b2b325036c3b`), v449 (`0ded1e5d04c8`) and v450 (`c19cc2d531e4`), on x86-64
  and on i386 under QEMU user mode, with the `dynarr` unit of
  `test/nilpy_dynarr/`. **On v449:** pass the call inline,
  `d.SumV(d.MakeArr(4))`, which v449 refuses too (see the row above), or leave
  the call to Pascal as that row says.

- **Nil Python: a class attribute returned from a method or a def came back as
  the wrong value.** With `class C:` holding `f = 2.5`, `s = "hi"`, `l = [1,
  2]` and `n = None`, `return C.f` (directly, or through a local first) was
  typed as the class. On x86-64 v449 printed `4612811918334230528` for `2.5`
  (its IEEE bits), numbers for the string and the list, and `0` for `None`; on
  i386, arm32 and hosted Xtensa (both ABIs) it refused the program, and so it
  did as an ESP object for riscv32 and Xtensa. Fixed in v450 (`b1b51f5a0d`).
  Measured on 2026-09-28 with v449 (`0ded1e5d04c8`) and v450 (`c19cc2d531e4`):
  v450 prints `2.5 hi [1, 2] None 2.5 hi`, as CPython does, on x86-64, i386,
  arm32, hosted riscv32 and hosted Xtensa with both ABIs under QEMU user mode,
  and builds the ESP objects; not measured on ESP silicon. `return
  type(self).k` is still refused, with `Nil Python: expected newline after
  statement`. **On v449:** read the attribute through the instance instead:
  `return self.f` (directly, or through a local) prints `2.5 hi None` for the
  float, string and `None` attributes with v449 on x86-64, i386 and arm32.

- **Nil Python: a Pascal `var` or `out` object parameter lost the object when
  the name held `None`.** `o = None`, then `d.NewInto(o, 5)`, a Pascal
  procedure that creates an object into its `var` parameter, then `print(o)`
  printed an empty line with v441 and v448: the object never reached `o`.
  After v448 (`9bd7f662e5`) the call is refused at compile time. A name that
  already holds an object gets the new one back with all three compilers:
  after `o = d.TB(1)` and `d.NewInto(o, 5)`, `o.v` is `5`. Measured as the
  row above. **On v448:** bind the name to an object first.

- **Nil Python for Xtensa with the call0 ABI did not build.** Every Nil Python
  program, even `x = 1` and `print(x)`, was refused when built with
  `--xtensa-abi=call0`: `target xtensa: addi immediate displacement 128 is
  outside the encodable range -128..127`, in the `builtin/pyeval.pas` that the
  compiler appends. Hosted xtensa (`--platform=posix`, run under qemu-xtensa)
  refused every Nil Python program on both ABIs, with `a heap arena needs
  mmap`. Both are fixed in v449 (`8529eb30e8`). Measured again on 2026-09-28
  with the pinned binaries, each in its own tree: v448 (`b2b325036c3b`), v449
  (`0ded1e5d04c8`) and v450 (`c19cc2d531e4`): v448 refuses `x = 1; print(x)`
  as a call0 ESP object (`addi`) and hosted on both ABIs (heap arena); v449
  and v450 build all four, and the hosted ones print `1` under qemu-xtensa. First measured on 2026-09-28 with v448 (`b2b325036c3b`) and the compiler built at
  `a5841bfb84` (`48b0ba0bb383`):

  | build | v448 | after v448 |
  | --- | --- | --- |
  | ESP object, call0 (`--platform=esp --no-signals --xtensa-long-calls`) | refused (`addi`) | builds |
  | ESP object, windowed, the same flags | builds | builds |
  | hosted, call0 and windowed (`--platform=posix --xtensa-soft-mulhigh --xtensa-long-calls`) | refused (heap arena) | `x = 1; print(x)` prints `1`, and `test/test_nilpy_cross32_values.py` matches its `.expected`, as on x86-64 |

  A Nil Python program on Xtensa needs `--xtensa-long-calls` on either ABI;
  without it the compiler stops and says so. Refused in v441 to v448. **On
  v448:** use the windowed ABI, as the ESP32-S3 examples do.

- **Nil Python on hosted riscv32 Linux.** Every Nil Python program was refused
  with `Nil Python is not supported on hosted riscv32 Linux yet`, so a Nil
  Python bug on the ESP32-C3's architecture could only be looked at on a board
  or in the ESP QEMU. It now builds and runs under qemu-riscv32, and the Nil
  Python cross-target test and the class-value test print the same output as
  x86-64. Measured on 2026-09-28 on the tree after pin v448. Fixed in v450
  (`d07cbfbb40`). Measured again on 2026-09-28 with a Nil Python program that
  returns class attributes: v449 (`0ded1e5d04c8`) refuses it with that
  message, and v450 (`c19cc2d531e4`) prints what CPython prints under
  qemu-riscv32. Refused in v441 to v448.

- **Pascal in the frozen-string mode: `Copy` returned an empty string.**
  Compiled with `-uPXX_MANAGED_STRING`, `s := Copy('abcdef', 1, 3)` into a
  `string[16]` left `Length(s)` at `0`, with no error, where FPC 3.2.2 gives
  `abc`. The default (managed) mode was right. Fixed in v450 (`13f122a0ef`).
  Measured on 2026-09-28 on x86-64: `0` and `[]` with v448 (`b2b325036c3b`)
  and v449 (`0ded1e5d04c8`), `3` and `[abc]` with v450 (`c19cc2d531e4`). The
  ESP bare-metal profile refuses that `Copy` at compile time with v449 and
  v450, so it never reached the wrong value there (measured on
  the ESP32-C3 and ESP32-S3 under QEMU). **On v449:** use the default string
  mode.

- **x86-64: the hardware random draw crashed on a CPU without RDRAND.**
  `__pxxHwRandom64`, the compiler's intrinsic behind the `random` unit's
  hardware tier, executed `RDRAND` even after `__pxxCpuHasHwRandom` had
  answered `False`, so a program that called it on an older x86-64 CPU (a
  Westmere Xeon) stopped with `SIGILL`. The `random` unit asks the probe first
  and was not affected. Fixed in v450 (`70f62b5544`). Measured on 2026-09-28
  under `qemu-x86_64 -cpu Westmere`, which has no RDRAND: a program that
  prints the probe and then draws once prints `probe FALSE` and dies with
  `Illegal instruction` (exit 132) with v448 (`b2b325036c3b`) and v449
  (`0ded1e5d04c8`), and prints `draw FALSE FALSE` with v450 (`c19cc2d531e4`).
  `Randomize; Random(1000)` from the `random` unit runs under that CPU model
  with all three. With `-cpu max` and on the host, all three draw. **On
  v449:** call `__pxxHwRandom64` only when `__pxxCpuHasHwRandom` is `True`, or
  use the `random` unit.

- **Nil Python: a float captured by a lambda or a nested def arrived as the
  wrong number.** `def bare(x): g = lambda: x; return g()` gave `0.0` for
  `bare(1.0)` on i386 and arm32; x86-64 and aarch64 were right. Fixed in v449
  (`dbd60352fd`). Measured on 2026-09-28 with
  `test/test_nilpy_a_captured_float_travels_by_its_bits.npy`, 13 rows compared
  with CPython: with v448 (`b2b325036c3b`), 5 rows wrong on i386 (for example
  `param 0.0` for `1.0` and `method 3.0` for `1.5`), the same on arm32 before
  it stopped (see the next row), and all 13 right on x86-64 and aarch64. With
  v449 (`0ded1e5d04c8`), all 13 match on x86-64, i386, arm32, aarch64, and
  hosted Xtensa with both ABIs, under QEMU user mode. The ESP value,
  `4.6071824188000174e+18` for `1.0`, is as reported in
  `devdocs/progress/LOGBOOK.md`; on ESP silicon the fix was reported on
  2026-09-28, in a report not yet recorded in the repository: v449 (`0ded1e5d04c8`,
  tree `5ea9d5ef07`) on a real ESP32-C3 and ESP32-S3, one image and one boot
  per chip, where the fixture's rows and `bare(1.0)` match CPython. **On
  v448:** call the nested def directly instead of taking it as a value; the
  fixture's `def direct` row is right with v448 on every target above.

- **Nil Python on arm32: a float default could stop the program with SIGBUS.**
  A default slot was not 8-byte aligned, and storing a float default into it
  faulted on arm32 once the layout shifted. Fixed in v449 (`4a9cf4c07c`).
  Measured on 2026-09-28 with the same test file under QEMU user mode on
  arm32: with v448 it stops with `Bus error` (exit 135) at the `def default`
  row; with v449 (`0ded1e5d04c8`) all 13 rows print.

- **Nil Python on the ESP32-S3: `cls(x)` inside a def or method lost its
  arguments.** With `cls = P`, `return cls(self.a)` gave an object whose `.a`
  was `0` or `None`, and `cls()` with no arguments then segfaulted. The
  ESP32-C3 and x86-64 were right. Module-level code was not affected. On the
  S3, v448 printed `0` (as reported in `devdocs/progress/LOGBOOK.md`). Fixed
  in v449 (`76d35e065f`). On silicon it was reported on
  2026-09-28, in a report not yet recorded in the repository: v449 (`0ded1e5d04c8`, tree
  `5ea9d5ef07`) on a real ESP32-C3 and ESP32-S3, one image and one boot per
  chip, where the class-value row and `cls()` match CPython. Measured on
  2026-09-28, hosted only: v448 cannot run Nil Python on hosted
  Xtensa (see the call0 row above), and with v449 (`0ded1e5d04c8`) a probe of
  `Q().mk().a` and a def-level `cls(3)` prints `7` and `3` on hosted Xtensa
  with both ABIs, as on x86-64. **On v448:** call the class by its name,
  `P(self.a)`, which is a direct call like the module-level form that was
  right; this was not measured on the S3.

- **Pascal: a string element passed to a `var` parameter wrote into shared
  memory.** `s := 'abc'; SetC(s[2])`, with `procedure SetC(var c: char)`,
  crashed with a segmentation fault, because the callee wrote into the
  literal's read-only bytes. With `u := t` sharing one buffer, it changed
  both. `Move` and `FillChar` into a string element did the same. FPC 3.2.2
  prints `ayc` and leaves the other copy alone. Fixed in v449 (`cbbb1e6418`).
  Measured on 2026-09-28 with
  `test/test_string_element_passed_by_ref_is_made_unique.pas`, 15 rows: with
  v448 it stops with a segmentation fault on x86-64, i386, arm32 and aarch64,
  and on riscv32 it runs and prints wrong values silently (`rc2 yefg yefg`,
  the alias changed too, where FPC prints `rc2 defg yefg`). With v449
  (`0ded1e5d04c8`) all 15 rows match FPC on those five targets. **On v448:**
  call `UniqueString(s)` before passing `s[i]` to a `var` parameter, `Move` or
  `FillChar`.

- **Pascal: a 33rd parameter crashed the compiler.** A routine, a method (32
  parameters plus `Self`) or a procedural type with more than 32 parameters
  stopped the compiler with a segmentation fault and no message. It is now
  refused with `too many parameters (33, max 32, counting Self for a method)`;
  the limit itself is unchanged. Fixed in v449 (`f619f705dd`). Measured on
  2026-09-28: `test_param_cap_routine_fail.pas`,
  `test_param_cap_method_fail.pas` and `test_param_cap_proctype_fail.pas`
  crash v448 (exit 139) and are refused with that message by v449
  (`0ded1e5d04c8`). 32 parameters, and 31 plus `Self`, compile and print what
  FPC 3.2.2 prints with both, on x86-64 and i386
  (`test_param_cap_at_the_limit.pas`). **On v448:** keep to 32 parameters,
  counting `Self`; pass a record for more.

- **TLS: a CA file that does not load was accepted.**
  `OpenSslTlsRegisterEx(True, '/nonexistent/ca.pem')` answered `True`, and
  so did a file that is not a certificate, so a mistyped private-CA path
  looked installed. Only the system store was used. Measured on 2026-09-28,
  built with `-dPXX_DYNLIB_LIBC` against the system libssl: `True` for both
  with pin v447, `False` for both with pin v448, on x86-64 and on i386 (QEMU
  user mode). With no CA file it answers `True` on both. On i386 v447 also
  crashed: the HTTPS example on
  [the networking page](../library/networking.md#openssl-backend)
  segfaulted, and with v448 it prints `status 200`. Wrong in v441 to v447
  (`9df5de0690`).

- **Pascal and Nil Python: a Pascal result that is `Self` or a new object
  leaked.** A method like `if V > 0 then Exit(Self); Result := TA.Create(1)`,
  called from Nil Python, was read as borrowed, so every new object it made
  was kept. Measured on 2026-09-28 with 500 calls whose results are
  discarded and 500 that rebind a name, inside a function: 500 objects still
  alive after the function returned with pin v447 (x86-64), 0 with pin v448
  on x86-64, i386 and arm32 (QEMU user mode). Wrong in v441 to v447
  (`180411ab1e`).

### Fixed in this release

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
  `Unhandled exception: <Class>: <Message>`, as on a desktop (`7eeb3d755`).
  Whether the chip should then stop or restart has not been decided.
  Currently the main task spins after the message:
  on the ESP32-C3 under QEMU with v451 the task watchdog fires, and the chip
  reboots and runs the program again (2026-09-29). On the ESP32-S3 under QEMU
  nothing followed the message for 60 s; whether that is the emulator is not
  known. See `devdocs/dev/nilpy-semantics-divergences.md`.
- **The five memory leaks** listed under [The pre-release leak sweep, and leaks fixed since](#the-pre-release-leak-sweep-and-leaks-fixed-since).

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

### The pre-release leak sweep, and leaks fixed since

Memory leaks were treated as release blockers for this beta. Before the release
every leak test in the tree was re-run. The Nil Python checks each ran beside a
deliberate leak, to prove they could catch one; the Pascal and C checks had no
such control at the time. The Pascal checks got one after v448 (`cfcfc49263`,
in v449): the same census, run with a string and an array kept on
purpose on each of 400 trips, must trip the bound. Measured on 2026-09-28 with
the compiler built at `a2614fcb8b`: 4 blocks live, and 1,080 with the
deliberate leak, on x86-64; 5 and 1,186 on i386 and arm32 (QEMU user mode).
The C checks still have no control. The re-run covered:

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

Found after the release, on 2026-09-27, in v441, and fixed since:

- **Nil Python: `list.clear()` and `dict.clear()` did not release what they
  dropped.** The elements, or the keys and values, stayed allocated after the
  list or dict itself was freed. A function that fills a list with 20 strings
  and clears it lost 20 strings per call. A buffer cleared and refilled in a
  loop does not grow, because refilling releases the old elements, but the
  last contents are lost when the buffer goes away. Fixed in v442
  (`fbfdcd1ea8`), in the runtime that the compiler links into every Nil Python
  program; measured fixed with v445. **On v441:**
  assign a new empty container (`buf = []`, `d = {}`) instead of calling
  `clear()`.
- **Nil Python: a computed string on the left of `*` leaked.** `str(i) * 2`,
  `"%d" % i * 2` and `s.upper() * 2` each lost one string per evaluation.
  Fixed in v446 (`c64b304036`). Measured on 2026-09-28 with
  `tools/census_at_exit.sh`, a 30-pass loop over `str(i) * 2` inside a
  function: 31 live with v445 (`caf21ac399f1`), 2 with v446
  (`ae3466a018d8`). **On v445 and earlier:** name the string first
  (`t = str(i)`, then `t * 2`).

Found on 2026-09-28, wrong in v441 to v448, and fixed in v449:

- **Pascal: a handled exception object was freed without running its
  destructor.** When an `except` block finished with the exception, its memory
  was released but its `Destroy` never ran, so anything the destructor frees
  was lost. That held for `on E: ... do`, a bare `except`, a `raise` caught
  one level further out, and a `try`/`finally` inside the `try`. An exception
  class that owns a `TStringList` lost the list on every raise. FPC 3.2.2 runs
  `Destroy` once in each case. Fixed in v449 (`846a574b00`). Measured again on
  2026-09-28 with the pinned binaries, each in its own tree: v448
  (`b2b325036c3b`), v449 (`0ded1e5d04c8`) and v450 (`c19cc2d531e4`): the same
  test counts 0 in every shape with v448, and matches its `.expected` with
  v449 and v450, on x86-64, i386 and arm32 (QEMU user mode). First measured on
  2026-09-28 with
  `test/test_a_handled_exception_runs_its_destructor_once.pas`: every shape
  counted 0 `Destroy` calls with v441 (`4ebfa2d047a2`) and v448
  (`b2b325036c3b`), and 1, as FPC 3.2.2 does, with the compiler built at
  `a2614fcb8b` (`5dea028059af`) on x86-64, i386 and arm32 (QEMU user mode).
  Its 500 raises of the owning class left 1,892 blocks live with v448 and 4
  with that compiler. **On v448 and earlier:** an exception class with no
  fields of its own that need freeing loses nothing, since the object's own
  memory is released.

A list or dict that a statement creates, such as `kept = []`, stays allocated
until that same statement runs again or the function returns. That holds even
after the name is bound to something else (`kept = []` a second time on
another line, `kept = None`, `kept = 5`), and calling a method on it
(`kept.append(r)`) holds it the same way. At module level it is held until
the program ends. It does not add up in a loop, but a function that fills a
list and then drops it keeps the contents until it returns. On an ESP32-C3
with about 70 KB free, 34 kept HTTP responses (about 1.4 KB each) held that
way ran the heap low enough that Wi-Fi stopped working. Fixed in v446
(`31d314dfa8`): the container is released as soon as the last name lets go of
it. v446 does not cover a list built by a comprehension
(`rows = [str(i) for i in range(n)]`): after `rows = None` it is still kept
until the function returns. That is fixed after v446 (`cdd6fd3c1f`, in v447).
Measured on 2026-09-28 with `tools/census_at_exit.sh`, a function whose list
of 30 strings is dropped before it exits: `kept = None` leaves 1 live with
v446 (`ae3466a018d8`); a comprehension then `rows = None` leaves 32 with v446
and 1 with the compiler at `e072d579b0` (`ccd62c91f30e`). **On v445 and
earlier, and for a comprehension on v446:** return from the function, or let
it end, to get the memory back.

`del name` on a local variable does not release what the name refers to; the
object stays allocated until the function returns. This is so from v446 to
v448, and fixed in v449 (`c4f5dcf929`). Measured again on 2026-09-28 with the
pinned binaries, each in its own tree: v448 (`b2b325036c3b`), v449
(`0ded1e5d04c8`) and v450 (`c19cc2d531e4`), a function that builds a list of
30 strings and exits inside the function: under `del`, 32 live with v448 and 1
with v449 and v450; under `= None`, 1 with all three; kept, 32 with all three.
On v446 to v448, assign `name = None` instead, which does release it. On v445
and earlier `name = None` does not release it either (see the paragraph
above): return from the function. (Measured on 2026-09-28, the same list of 30
strings: under `del` 32 live with v446 and with the compiler at `e072d579b0`;
under `= None` 1 with both, and 32 with v445. Measured again with
`tools/census_at_exit.sh`, the census taken inside the function: under `del`
32 live with v448 (`b2b325036c3b`) and 1 with the compiler built at
`a2614fcb8b` (`5dea028059af`), under `= None` 1 with both, and 32 with both
when the list is kept.)

### ESP networking under load

Networking was soaked under Espressif's QEMU with the v440 compiler (v441
differs from it only in the `Dispose(F())` fix). None of these runs showed
memory or sockets growing:

| what ran | chip | result |
| --- | --- | --- |
| 10,000 HTTP requests with `urequests` (Nil Python) | ESP32-S3 | 64 bytes in total over 10,000 requests |
| 1,000 sessions each of `ntptime`, `umqtt.simple` and `umqtt.robust` (Nil Python) | ESP32-S3 | 0 bytes per session |
| 3,000 MQTT sessions with `umqtt.simple` (Nil Python) | ESP32-C3 | the same socket number every session; heap flat after the first 25 |
| 320 TCP connections over loopback, server and client in Pascal | ESP32-S3 | 0 bytes over 40 passes |
| 300 HTTPS requests with `urequests` (Nil Python; v442 or later) | ESP32-S3 (QEMU) | 68 bytes in total over 300 requests |
| 300 HTTPS requests with `urequests` over Wi-Fi (Nil Python; v442) | ESP32-C3 board | no growth: free heap level at about 65 KB throughout |

Each run was checked against a deliberate leak, which it caught. An earlier
reading of about 0.6 bytes per pass on the Nil Python example programs turned
out to be the soak's own report lines, one kept string per checkpoint line (see
the Nil Python paragraph above). With those lines moved into a function, the
four Nil Python examples keep 0 bytes after 10, 160, 640 and 1,280 passes on
both chips, with v441, beside a deliberate leak that reads 76 bytes per pass.
A MicroPython-style main loop written at module level, making 1,000 requests
with a `print` each time, holds about 1.6 KB once (the last response, still
bound to its variable, as in CPython) and then stays level.

Two limits apply to these measurements:

- **Over real Wi-Fi, two boards and two libraries have been measured**; the
  rows above ran over QEMU's emulated Ethernet. On 2026-09-28, with the
  compiler built from tree `cdd6fd3c1f` (sha256 `139494b2b863`; pin v447
  contains that tree, v446 does not), a physical ESP32-S3 made 300
  `urequests` fetches over a home Wi-Fi network. At every checkpoint its free
  heap was between 12 bytes lower and 328 bytes higher than at the start, and
  130 seconds after the last fetch it was 216 bytes higher. Both an ESP32-C3
  and an ESP32-S3 ran 300 `umqtt.simple` sessions against a broker on that
  network, 0 errors each. Each MQTT run was about 1.3 KB short while
  connections were closing (the S3 briefly 4.7 KB at session 200, back to
  1.3 KB by 300), and 130 seconds after the last session had about 1.9 KB
  more free heap than at the start. The positive controls, which keep every
  response or session on purpose, lost 1,438 bytes per fetch and 1,116 to
  1,142 bytes per session, so the measurement would have seen a leak.
  Longer runs the same day, with the compiler of tree `577e7acf0e`: 10,000
  `urequests` fetches on the ESP32-C3 ended using 120 bytes more heap
  than at the start, and were never more than 320 bytes away; 3,000
  `umqtt.simple` sessions on the ESP32-S3 ended with 2,056 bytes more free. Both
  runs had no errors and never rebooted. On
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
  and one from after it alike. The C3 HTTPS figure in the table above is from
  the board, over Wi-Fi. **Workaround:** run long network tests under QEMU on
  the ESP32-S3, or keep a C3 run short. With pin v451 on 2026-09-29,
  `tools/esp_qemu_urequests.sh nilpy-c3` went silent after 500 of its 1,000
  requests, while the same command with `UREQ_N=200` completed and
  `tools/esp_qemu_urequests.sh nilpy-s3` completed all 1,000. When the chip
  goes silent, that script waits for `UREQ_TIMEOUT` (1,800 seconds by default)
  before it reports the failure.
