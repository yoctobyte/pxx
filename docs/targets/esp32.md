---
title: ESP32 / Microcontrollers
order: 65
---

# ESP32 and Microcontroller Targets

PXX cross-compiles Pascal to the two ESP32 CPU families with no vendor
compiler in the loop:

| Chip | CPU | PXX target |
| --- | --- | --- |
| ESP32-C3 | RISC-V (RV32IMC) | `--target=riscv32` |
| ESP32-S2 / S3 | Xtensa LX7 | `--target=xtensa` |

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

  **`Str` of a float is still refused, deliberately**, and the diagnostic says
  which arm is missing:

  ```
  pascal26:3: error: Str: StrFloat not loaded
  ```

  Float formatting needs `PxxSciDigits17` and therefore the whole softfloat
  library, which this profile skips so a program that never touches a float does
  not pay ~54–64 KB of flash for the option. Add `uses softfloat;` if you want
  it — the same unit the [Floating point](#floating-point) section describes.

  An `Assert` message can now carry the value that failed, which is what this was
  really about on a board with no debugger:

  ```pascal
  Str(n, s);
  Assert(n > 99, 'count too low: ' + s);   { prints: count too low: 3 (f.pas, line 5). }
  ```

  `sysutils.IntToStr` is still not reachable here — `sysutils` is not available
  on this profile — so `Str` is the route.
- **The heap is a fixed static arena, 64 KiB by default, and it is the single
  largest thing in a bare image's SRAM.** Size it with one of
  `-dPXX_ESP_HEAP_8K`, `-dPXX_ESP_HEAP_16K`, `-dPXX_ESP_HEAP_32K`,
  `-dPXX_ESP_HEAP_128K`. Measured on an esp32c3 hello-world, total bss:

  | | 8K | 16K | 32K | 64K (default) | 128K |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | bss | 13,592 | 21,784 | 38,168 | 70,936 | 136,472 |

  Running out is reported, not silent: the program writes
  `pxx: out of memory (bare static heap arena exhausted; HEAP_ARENA)` to UART0
  and halts with code 203. Note the compiler cannot check this for you —
  it refuses a build whose image plus arena plus stack does not FIT, but an
  arena that fits and is too small for your program is only found at runtime.
- **A program that never allocates can drop the heap entirely with
  `-uPXX_MANAGED_STRING`, and on bare metal that is the single largest saving
  available.** Measured on an esp32c3, a UART-only program using `ShortString`
  and no `GetMem`:

  | | code | data | bss |
  | --- | ---: | ---: | ---: |
  | default | 58,900 | 736 | 71,452 |
  | `-uPXX_MANAGED_STRING` | **1,156** | 432 | **5,288** |

  Byte-identical output from both. It is not automatic yet — every Pascal
  program pulls the managed-string runtime unconditionally, and `{$H-}` does
  not reach it. **Getting it wrong is a COMPILE error, never a bad binary**: a
  program that does need the runtime fails with `frozen tyString concat
  unsupported` rather than miscompiling, so it is safe to try and see.
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

Measured on **2026-08-30 with pinned `v393`** (empty program, `--esp-profile=bare`).
Re-measure rather than trust the table — these have roughly doubled since they
were first published, and a figure without a pin behind it is a promise nobody
renewed:

```sh
pxx --target=esp32c3 --esp-profile=bare empty.pas out    # prints code/data/bss
```

| | code | data | bss |
| --- | --- | --- | --- |
| esp32c3 (riscv32) | ~50 KB | 344 B | ~104 KB |
| esp32s3 (xtensa) | ~43 KB | 344 B | ~104 KB |

What that buys you — the floor is not "hello world plus bloat", it is the
full managed runtime:

- **Heap**: a fixed 64 KiB static arena (the bulk of that bss figure).
  `New`/`Dispose`/`GetMem`/dynamic arrays work on bare metal.
- **Managed strings**: `AnsiString` with reference counting works on bare
  metal, including on the C3's boot path.
- The remainder of that bss figure is runtime globals — exception state and
  similar. It has grown faster than the arena and is tracked as
  a compiler-size problem, not an ESP one; see the emission-size work on the
  board rather than treating the number here as a target.

An ESP32-C3 has roughly 400 KB of usable SRAM, so a minimal PXX image plus
stack currently sits around a quarter of it. That is comfortable but no longer
negligible, and it is the honest way to say it — an earlier version of this page
claimed "well under a quarter" against a bss figure that has since grown by
about half.

## Floating point

The ESP cores are compiled without FPU codegen; float operations lower to
integer soft-float kernels. On bare images this support is **opt-in** so
programs that never touch floats do not pay for it:

```pascal
uses softfloat;   { Double/Single arithmetic; ~54 KB of code on xtensa, ~64 KB on riscv32 }
```

Without the unit, float operations fail at compile time with a clear error
rather than silently linking the kernels in. 64-bit integer arithmetic
(`Int64`/`UInt64`, including multiply, divide and shifts) is always
available and validated against the x86-64 oracle.

**`Real` is `Single` here, not `Double`.** These cores have no hardware double,
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
works on the bare profile of both chips; an unhandled `raise` halts the
program. Generators on any non-x86-64 target must use the stackless
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

- [Cross-compilation](./cross-compilation.md)
- [Targets overview](./)
