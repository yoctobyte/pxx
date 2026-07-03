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

## Code size and memory footprint

Measured with the pinned compiler (empty program, bare profile):

| | code | data | bss |
| --- | --- | --- | --- |
| esp32c3 (riscv32) | ~26 KB | 48 B | ~70 KB |
| esp32s3 (xtensa) | ~21 KB | 48 B | ~70 KB |

What that buys you — the floor is not "hello world plus bloat", it is the
full managed runtime:

- **Heap**: a fixed 64 KiB static arena (the bulk of that bss figure).
  `New`/`Dispose`/`GetMem`/dynamic arrays work on bare metal.
- **Managed strings**: `AnsiString` with reference counting works on bare
  metal, including on the C3's boot path.
- The remaining ~6 KB of bss is runtime globals (exception state and
  similar).

An ESP32-C3 has roughly 400 KB of usable SRAM; a minimal PXX image plus
stack uses well under a quarter of it.

## Floating point

The ESP cores are compiled without FPU codegen; float operations lower to
integer soft-float kernels. On bare images this support is **opt-in** so
programs that never touch floats do not pay for it:

```pascal
uses softfloat;   { Double/Single arithmetic, ~50 KB of code }
```

Without the unit, float operations fail at compile time with a clear error
rather than silently linking the kernels in. 64-bit integer arithmetic
(`Int64`/`UInt64`, including multiply, divide and shifts) is always
available and validated against the x86-64 oracle.

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
