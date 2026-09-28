---
title: ESP32 / Microcontrollers
order: 65
---

# ESP32 and Microcontroller Targets

PXX cross-compiles Pascal, C and Nil Python to the two ESP32 CPU families
with no vendor compiler in the loop:

| Chip | CPU | PXX target | How far it has been tested |
| --- | --- | --- | --- |
| ESP32-S3 | Xtensa LX7 | `--target=xtensa` or `--target=esp32s3` | examples run on a physical board |
| ESP32-C3 | RISC-V (RV32IMC) | `--target=riscv32` or `--target=esp32c3` | examples run on a physical board |
| ESP32-S2 | Xtensa LX7 | `--target=esp32s2` | compiled only |
| ESP32 (classic) | Xtensa **LX6** | `--target=esp32` | examples run on a physical board |

The other chip names (`esp32c2`, `esp32c6`, `esp32h2`, `esp32p4`) are
accepted and compile to an ESP-IDF object, but nothing has been run on them.

All 36 example projects, with the chip and language of each and where each
last ran (QEMU or a board), are listed in
[Examples: all 36 ESP32 examples](../examples/index.md#all-36-esp32-examples).

**The classic ESP32 now runs on silicon; the S2 is still compiled only.**
Measured 2026-09-27 on tree `5b4e7381dc` with compiler sha256
`4ebfa2d047a2` (the release pin v441's own binary), flashed to an
**ESP32-D0WD-V3 rev v3.1** (dual-core LX6 at 240 MHz, MAC `e0:8c:fe:57:bb:b8`,
CP2102 bridge): `--target=esp32` compiles
`examples/esp32/hello-esp32/main/main.pas` to a relocatable object
(`code=24579B data=4672B bss=1336B`, the same code size as the identical source
for `--target=esp32s3`), that object links into a 166,752-byte ESP-IDF v6.0.1
image with `app_main` at `0x400d9854`, and the board prints its five
`PXX hello from Pascal ESP32: i=N` lines and `PXX ESP32 sum 1..5 = 15`. No
fault, no panic, first attempt.

That first run was one program. It has since been widened on the same board, all
of it with compiler sha256 `ccca045a848b` (pin v442's own binary —
v441 plus the output-path fix in `a1859b8b69`, which does not touch code
generation). The tree moved during the work, so the compiler rather than a single
tree sha is what these rows have in common; the tooling shas that matter are
called out where they do. Five programs, all on the classic part:

| Program | What it exercises | Verified against |
| --- | --- | --- |
| `examples/esp32/hello-esp32/main/main.pas` | `esp_rom_printf`, `gpio_*`, `vTaskDelay`, integer arithmetic | expected serial output |
| `test/test_esp_idf_nested_try.pas` | two or more live exception frames at once, each row raising *through* the outer frame's saved `EXC_TOP` link, on the **windowed** Xtensa ABI | **the x86-64 oracle, 10 lines, byte-identical** |
| `examples/esp32/timer-s3/main/main.pas` | `esp_timer` callbacks into Pascal | expected serial output |
| `test/test_esp_string.pas` | managed `AnsiString`: literal via `PXXStrFromLit`, `Length` at handle−8, char index, a refcounted copy | **the x86-64 oracle, 3 lines, byte-identical** |
| `examples/esp32/nilpy-esp32` (Nil Python) | a class with methods, a list of instances, a `for` loop, `print`, `//`, `len` | **`main/main.expected`, 4 lines, byte-identical — and that file is CPython's own output** |

Three of the five are therefore a real byte comparison, which the first run could
not claim. The other two are not: `esp_flash.sh` degrades to `--no-verify` by
itself, and says so, when a program's externals do not exist on x86-64, so for
those the evidence is the expected serial output. The NilPy program needs
`--xtensa-long-calls`; without it `PyUtf8CpAt` overflows the CALL0/CALL8 ±512 KiB
reach. That is not an LX6 defect — `--target=esp32s3` gives the identical
message — it is the documented remedy for a large single unit.

A heap soak ran on the same board and the same pin:
`tools/esp_heap_soak.sh hello-esp32`, 10 passes, read `delta=0 bpp=0`, and the
same soak with `--control` read `delta=764 bpp=76` — 64 requested bytes plus the
12-byte allocator header, the figure already measured on the C3 and S3. The
control matters more than the zero: it shows the instrument can see a leak of
that size in that program, so the zero is a measurement and not a silence.

The nested-exception row is the most useful of the five for this chip
specifically. It is the measured reproducer for the windowed-frame bug fixed in
`XtensaExcFrameAddrW` (`compiler/ir_codegen_xtensa.inc`), where a pushed
exception frame's spills overwrote the outer frame's saved `EXC_TOP` link and the
next raise that had to cross it faulted with `LoadProhibited`. The windowed ABI
is the LX6 and LX7's shared inheritance, so a chip that runs this is exercising
the register-window path and not just arithmetic and `printf`.

**Every row above was re-run with a working reboot guard, and each saw exactly
one boot.** That needs saying because for a while they were not. The guard in
`tools/esp_flash.sh` counted the string `ESP-ROM`, which the classic ESP32's boot
ROM never prints — it prints `ets Jul 29 2019` and `rst:0x1 (POWERON_RESET)` — so
on `--chip esp32` it read zero boots every time and its `>= 2` test could not
fire. It printed OK as silence rather than as evidence, which is the dangerous
polarity: a program that panicked and restarted while reprinting its first lines
would have passed a prefix comparison, and that is the exact case the guard
exists to catch. It now counts `rst:`, which all three parts print (`d5c6f81e7e`),
and the verdict lines carry `[rst: N]` so every row records what the guard saw
(`c0fd4fa032`, confirmed on this board: `OK — board output matches the x86-64
oracle (3 lines) [rst: 1]`, that confirmation run being on pin v443 rather than
v442). Measured on this board, all five rows read `rst: = 1`, so esptool's own
reset falls outside the capture window and the `>= 2` threshold keeps full
resolution: 1 is one clean boot, 2 is a reboot. Before the fix the count was read
out of the guard's own expanded test under `bash -x`, because it was deleted with
the capture and only printed on a FAIL — a passing row carried no evidence at
all, which is what `c0fd4fa032` corrects. The same bug, with the
same inverted polarity, was fixed in `examples/esp32/nilpy-c3/build.sh` in
`0db876e74b`, where it made the guard *unsatisfiable*: `nilpy-esp32`'s output
matched `main.expected` byte for byte and the script still reported FAIL.

What this still does **not** say. It is five programs, not the RTL: floating
point, files, and most of the container surface are untouched on this chip.

**Four ports on pin v448, two of them failing.** On 2026-09-28 the same board
ran `examples/esp32/timer-esp32`, `uart-esp32`, `nilpy-hw-esp32` and
`gpio-edge-esp32` (compiler sha256 `b2b325036c3b`), each with the same source
as its S3 or C3 original. `timer-esp32` matches its `main.expected` byte for
byte, which replaces the by-eye check of the timer row above. `uart-esp32`
passes 10 of its 13 checks, and one of the failures is the control that
the pad-echo check depends on. The two Nil Python programs reset in a `TG1WDT`
watchdog loop before printing anything, both inside `_xt_context_save`, while
the same programs pass on the S3 and the C3. They are kept as reproducers. The
details are in
[Examples: on a classic ESP32](../examples/index.md#on-a-classic-esp32).

One observed flake, recorded at the weight of its evidence. Twice, an `esp_flash.sh`
write to this board failed with `esptool could not write <port>. Hold BOOT while
tapping RESET to force download mode, then retry.`, and both times the next
attempt succeeded. Both failures were the first write after the board had been
left running a program that ends in `while True do vTaskDelay`, which points at
auto-reset timing into download mode rather than at anything in pxx. That is
**n=2 and was not deliberately reproduced**, so it is a lead, not a diagnosis.
Deliberately not worked around: a retry loop inside `esp_flash.sh` would also
paper over a board that genuinely cannot be written, which is the case its
current message correctly tells you how to fix.

`--esp-profile=bare` is still refused by name for this chip, correctly: the
bare image hardcodes the C3/S3 load address and a UART0 base of `$60000000`,
where the classic part's is `$3FF40000`. Use the IDF profile.
`tools/esp_flash.sh --chip esp32` drives it.

There are two integration modes.

## Mode 1: Bare metal (`--esp-profile=bare`)

Produces a self-contained ELF linked at the SoC SRAM map. No ESP-IDF, no
FreeRTOS, no linker: the program owns startup (stack setup) and runs directly
from RAM. QEMU boots it with `-kernel`.

**The bare profile is a test vehicle and runs under QEMU only. On a real
board, use the ESP-IDF mode below.** Measured on an ESP32-S3 on 2026-09-25: a
bare image boots and reaches `main`, but the first byte-sized memory access
faults, because the S3 only allows 32-bit accesses where the bare profile
places its data. Byte writes to the UART are also dropped. A bare ESP32-C3
image has never been run on silicon.

With the program below saved as `esphello.pas`:

```sh
./pxx --target=riscv32 --esp-profile=bare esphello.pas esphello.elf
tools/esp_run_bare.sh --chip esp32c3 esphello.pas     # compile + boot under QEMU
```

Under the bare profile the compiler defines `PXX_ESP_BARE`, so one source
file can serve both the device and a desktop oracle build:

```pascal
program EspHello;

{$ifdef PXX_ESP_BARE}
{ Bare metal: write a byte straight to the UART0 TX FIFO (MMIO). }
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

begin
  PutS('hello esp32');
  PutC(10);
{$ifdef PXX_ESP_BARE} while True do ; {$endif}
end.
```

This is exactly how the project's own gate works: `make test-esp-bare`
compiles the same source for x86-64 and for both chips, boots the chip images
under Espressif QEMU, and diffs the raw UART bytes against the desktop run.

Notes for the bare profile:

- `writeln`/`readln` are intentionally no-ops — there is no console. Output
  goes through your own UART writes, as above.
- **`Str` works for every type except floats.** The five non-float formatters
  live in `compiler/builtin/strfmt.pas`, which this profile pulls on its own when
  it sees `Str(`, so integers, unsigned, `Char`, `Boolean`, strings and field
  widths all format here:

  ```pascal
  var s: AnsiString; n: Int64;
  begin
    n := -4095;  Str(n, s);     { '-4095' }
    n := 42;     Str(n:6, s);   { '    42' — padded on the left }
  end.
  ```

  Verified by booting the same source on esp32c3 and esp32s3 under Espressif
  QEMU and diffing the UART bytes against the x86-64 run
  (`test/test_esp_bare_str.pas`), so this is output equality and not just a
  successful compile.

  **`Str` of a float is refused on this profile**, and the diagnostic says
  which part is missing:

  ```
  pascal26:5: error: Str: StrFloat not loaded
  ```

  `uses softfloat;` does not change that: float formatting lives in a runtime
  unit this profile does not load. To print a float, scale it and format the
  integer: `Str(Trunc(d * 100), s)` gives `450` for `d = 4.5`.

  An `Assert` message can now carry the value that failed, which is what this was
  really about on a board with no debugger:

  ```pascal
  Str(n, s);
  Assert(n > 99, 'count too low: ' + s);   { prints: count too low: 3 (f.pas, line 5). }
  ```

  `sysutils.IntToStr` is still not reachable here — `sysutils` is not available
  on this profile — so `Str` is the route.
- **The heap is a fixed static arena, 64 KiB by default.** It is linked in
  only when the program allocates (a managed string, `GetMem`, a dynamic
  array); a program that does not allocate has no arena at all. When it is
  there, it is the largest thing in a bare image's SRAM. Size it with one of
  `-dPXX_ESP_HEAP_8K`, `-dPXX_ESP_HEAP_16K`, `-dPXX_ESP_HEAP_32K`,
  `-dPXX_ESP_HEAP_128K`. Measured with v445 on 2026-09-27 on the concat and
  `GetMem` program below, total bss, the same on both chips and the same as
  with v425:

  | | 8K | 16K | 32K | 64K (default) | 128K |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | bss | 9,472 | 17,664 | 34,048 | 66,816 | 132,352 |

  Running out is reported, not silent: the program writes
  `pxx: out of memory (bare static heap arena exhausted; HEAP_ARENA)` to UART0
  and halts with code 203. Note the compiler cannot check this for you —
  it refuses a build whose image plus arena plus stack does not FIT, but an
  arena that fits and is too small for your program is only found at runtime.
- **`-uPXX_MANAGED_STRING` removes the managed-string runtime** from a
  program that does not need it. The saving is now small, because unused
  runtime code is dropped anyway. Measured with v445 on 2026-09-27 on the
  hello program above, code bytes (v425 gave 12 bytes less on the esp32s3):

  | | esp32c3 | esp32s3 |
  | --- | ---: | ---: |
  | default | 3,668 | 3,500 |
  | `-uPXX_MANAGED_STRING` | 892 | 1,336 |

  With `ShortString` instead of `AnsiString` the program is already under
  1.4 KB and the flag changes nothing. **Getting it wrong is a compile error,
  never a bad binary**: a program that does need the runtime fails with
  `frozen tyString concat unsupported` rather than miscompiling, so it is safe
  to try. One exception on pin v449: in this mode `Copy` returns an empty
  string (`Copy('abcdef', 1, 3)` has length 0, where the default mode and FPC
  give `abc`). It is fixed on master after v449, in `13f122a0ef`. Measured on x86-64 on 2026-09-28: `0` and empty with v449,
  `3` and `abc` with a compiler built from `a49f6f12c6`.
- On the ESP32-S3, a bare program that declares a `Double` and uses managed
  strings builds and runs under QEMU from pin v425 (re-run with v445). With v424 it could fail to
  build with `j displacement … is outside the encodable range
  -131072..131071`; on v424, keep floats out of such a program, or build it as
  an ESP-IDF component.
- A program that falls off the end parks in a self-loop (there is no OS to
  exit to). End interactive experiments with `while True do ;`.
- Interrupt handlers: mark a routine `interrupt;` for a raw hardware-vector
  handler (riscv32, and xtensa under the Call0 ABI).

## Mode 2: ESP-IDF component (`--emit-obj`)

Compiles to a relocatable object (`main.o`) whose exported `app_main` is
called by ESP-IDF's startup task. Externals such as `esp_rom_printf` and
`vTaskDelay` resolve at IDF link time; FreeRTOS, Wi-Fi and the vendor
peripheral drivers stay available. See `examples/esp32/hello-c3/` and
`examples/esp32/net-c3/` for complete buildable projects.

The peripheral units (GPIO, UART, ADC, PWM, I2C, NVS, timers and the
interrupt event queue) are documented in
[ESP32 peripherals](../library/esp.md).

```pascal
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
```

`writeln` and `readln` WORK on this profile (unlike the bare one, further
down): they go through the libc stdout/stdin streams that ESP-IDF's console
sets up, so ordinary Pascal I/O reaches the serial monitor. `esp_rom_printf`
above remains available and is what IDF's own code uses; either is fine.

Two consequences of using the STREAMS rather than a file descriptor, both of
which the runtime is stuck with rather than choosing:

- **End every line with a newline.** stdout is line-buffered, and a program
  that ends leaves a partial final line unflushed.
- `write(1, ...)` is NOT the console. Under IDF, fd 1 is not the console's
  descriptor — the standard streams hold whatever fd `open()` returned — so
  raw POSIX writes to 1 answer `EBADF` while the streams work.

## Code size and memory footprint

Measured with **pin v445** (compiler sha256 `caf21ac399f1…`) on 2026-09-27,
`--esp-profile=bare`. The compiler prints the figures on its `ok:` line:

```sh
./pxx --target=esp32c3 --esp-profile=bare prog.pas prog.elf
```

| Program | Chip | code | data | bss |
| --- | --- | ---: | ---: | ---: |
| empty (`begin end.`) | esp32c3 | 20 B | 344 B | 640 B |
| empty | esp32s3 | 94 B | 344 B | 640 B |
| hello, above (UART writes, `AnsiString`) | esp32c3 | 3,668 B | 536 B | 1,276 B |
| hello, above | esp32s3 | 3,500 B | 536 B | 1,276 B |
| a string concat and a `GetMem` | esp32c3 | 13,924 B | 568 B | 66,816 B |
| a string concat and a `GetMem` | esp32s3 | 11,372 B | 568 B | 66,816 B |

The concat and `GetMem` program:

```pascal
program sc;
var s: AnsiString; p: Pointer;
begin
  s := 'ab';
  s := s + 'cd';
  GetMem(p, 16);
end.
```

Compared with v425, data is 8 bytes larger in every program; code for the
empty and hello programs on the esp32c3 is unchanged. The v425 concat figures
came from a program this page did not show, so they are not comparable.

Unused runtime code is dropped, so a program pays for what it uses. The big
step is the first allocation, which brings in the allocator and the 64 KiB heap
arena (the bulk of that bss). Managed strings with reference counting, `New`,
`Dispose`, `GetMem` and dynamic arrays all work on bare metal.

An ESP32-C3 has roughly 400 KB of usable SRAM, so a program that allocates
starts at about a fifth of it with the default arena, most of which is the arena
itself. `-dPXX_ESP_HEAP_16K` brings that down to under a tenth.

## Floating point

The ESP cores are compiled without FPU codegen; float operations lower to
integer soft-float kernels. They are linked in when a program uses a float and
not otherwise, with no `uses` needed. Measured with v445 on bare images, this
program is 16,232 bytes of code on the esp32c3 and 14,564 on the esp32s3:

```pascal
program fd;
var d: Double; n: Integer;
begin
  d := 1.5;
  d := d * 3.25;
  n := Trunc(d);
  if n = 4 then d := 0;
end.
```

The same program with `Int64` in place of the `Double` (`d := 15; d := d * 3;
n := d;`) is 312 and 331 bytes. 64-bit integer arithmetic (`Int64`/`UInt64`, including
multiply, divide and shifts) is always available and validated against the
x86-64 oracle.

**`Real` is `Single` here, not `Double`**, on both ESP chips and on riscv32
Linux. These cores have no hardware double,
so `Real` — the type that means "the native float of this machine" — is the
4-byte one. `SizeOf(Real)` is 4, an `array of Real` strides by 4, and `Real`
arithmetic carries about 7 decimal digits. This is deliberate: it keeps
`Real` code on the cheaper soft-float kernels, and `Double` remains available
by name for the places that genuinely need the precision and can afford it.

The trap worth knowing about is shared data. A record containing a `Real`
does not have the same layout on an ESP32 and on the x86-64 host it talks to.
Name `Single` or `Double` explicitly in anything you serialise, log in binary,
or map onto a struct the other side also declares.

See [Types](../language/types.md#real-is-the-targets-native-float).

## Generators and language features

Most of the shared-IR language surface works on the ESP targets: records,
sets, 64-bit integers, dynamic arrays, proc-typed variables (indirect
calls), `@proc`, and stackless generators. Classes (with virtual dispatch)
work on both ESP targets. `try`/`except`/`finally` (including re-raise)
works on the bare profile of both chips. An unhandled exception prints
`Unhandled exception: <Class>: <Message>`, as on a desktop, and the program
stops (the fix, `7eeb3d755`, is in every pin from v441; see [Known issues](../reference/known-issues.md#fixed-in-this-release)). Generators on any non-x86-64 target must use the stackless
form:

```pascal
uses slgen;   { the stackless-generator runtime unit }

function Squares(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;
```

## Guard rails for small RAM

- `--max-stack-frame=N` (default 1 MB — tighten it for a micro) warns when
  any routine's stack frame exceeds the threshold; `{$MAXSTACKFRAME n}` sets
  it per-file. A 400 KB SRAM part deserves something like
  `--max-stack-frame=16384`.
- The heap arena is a compile-time constant (64 KiB). Exhausting it fails
  allocation rather than corrupting neighbours.

## Next

- [ESP32 peripherals](../library/esp.md)
- [The ESP32 IDE](../getting-started/esp-ide.md)
- [Cross-compilation](./cross-compilation.md)
- [Targets overview](./index.md)
