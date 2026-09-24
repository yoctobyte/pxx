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
| ESP32-C3 | RISC-V (RV32IMC) | `--target=riscv32` or `--target=esp32c3` | examples run under Espressif's QEMU |
| ESP32-S2 | Xtensa LX7 | `--target=esp32s2` | compiled only |

The other chip names (`esp32`, `esp32c2`, `esp32c6`, `esp32h2`, `esp32p4`) are
accepted and compile to an ESP-IDF object, but nothing has been run on them.

There are two integration modes.

## Mode 1: Bare metal (`--esp-profile=bare`)

Produces a self-contained ELF linked at the SoC SRAM map. No ESP-IDF, no
FreeRTOS, no linker: the program owns startup (stack setup) and runs directly
from RAM. QEMU boots it with `-kernel`; on hardware you load it like any
RAM image.

```sh
./pxx --target=riscv32 --esp-profile=bare blink.pas blink.elf
tools/esp_run_bare.sh --chip esp32c3 blink.pas     # compile + boot under QEMU
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
  `-dPXX_ESP_HEAP_128K`. Measured with v424 on a program that concatenates a
  string and calls `GetMem`, total bss, the same on both chips:

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
  runtime code is dropped anyway. Measured with v424 on the hello program
  above, code bytes:

  | | esp32c3 | esp32s3 |
  | --- | ---: | ---: |
  | default | 3,668 | 3,452 |
  | `-uPXX_MANAGED_STRING` | 892 | 1,288 |

  With `ShortString` instead of `AnsiString` the program is already under
  1.4 KB and the flag changes nothing. **Getting it wrong is a compile error,
  never a bad binary**: a program that does need the runtime fails with
  `frozen tyString concat unsupported` rather than miscompiling, so it is safe
  to try.
- **Fixed after v424:** on the ESP32-S3, a bare program that declares a
  `Double` and uses managed strings could fail to build with `j displacement …
  is outside the encodable range -131072..131071`. The development tree builds
  and runs it. On v424, keep floats out of an S3 bare program that uses
  `AnsiString`, or build it as an ESP-IDF component.
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

Measured with **pin v424** on 2026-09-25, `--esp-profile=bare`. The compiler
prints the figures on its `ok:` line:

```sh
./pxx --target=esp32c3 --esp-profile=bare prog.pas prog.elf
```

| Program | Chip | code | data | bss |
| --- | --- | ---: | ---: | ---: |
| empty (`begin end.`) | esp32c3 | 20 B | 336 B | 640 B |
| empty | esp32s3 | 58 B | 336 B | 640 B |
| hello, above (UART writes, `AnsiString`) | esp32c3 | 3,668 B | 528 B | 1,276 B |
| a string concat and a `GetMem` | esp32c3 | 19,416 B | 480 B | 66,816 B |
| a string concat and a `GetMem` | esp32s3 | 15,720 B | 480 B | 66,816 B |

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
not otherwise, with no `uses` needed. Measured with v424 on bare images, a
program that multiplies a `Double` and truncates it is 15,644 bytes of code on
the esp32c3 and 14,084 on the esp32s3. The same program with `Int64` in place
of the `Double` is 544 bytes on both. 64-bit integer arithmetic (`Int64`/`UInt64`, including
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
works on the bare profile of both chips. An unhandled exception does not print
a message: see [Known issues](../reference/known-issues.md#esp-an-uncaught-exception-does-not-report-itself). Generators on any non-x86-64 target must use the stackless
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
- [Cross-compilation](./cross-compilation.md)
- [Targets overview](./index.md)
