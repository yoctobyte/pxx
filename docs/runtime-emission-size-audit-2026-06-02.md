# Runtime Emission Size Audit - 2026-06-02

This is a dated rainy-afternoon note. It is not active work.

## Why This Was Checked

The Pascal hello-world ELF grew from the early self-host baseline to 1,134
bytes. For Linux this is still tiny. For future microcontroller targets such as
ESP32-class boards, Arduino-class systems, and possibly smaller PIC-class
devices, every emitted runtime feature should justify its presence.

The audit confirms that the growth is optional support code, not an
architectural obstacle.

## Current Hello-World Accounting

Command:

```sh
./compiler/pascal26 test/hello.pas /tmp/hello
```

The generated static ELF64 executable contains one program header and no
section table:

| Region | Bytes |
| --- | ---: |
| ELF header + program header | 120 |
| Heap startup + jump over helper region | 111 |
| Managed `AnsiString` helper region | 749 |
| Actual hello-world body | 106 |
| Data | 48 |
| **Total** | **1,134** |

The plain hello program does not allocate managed strings and never calls the
749-byte helper region. It also does not allocate from the heap, but startup
still reserves a Linux `mmap` arena.

## Historical Breakpoints

Reconstructed by compiling `test/hello.pas` with FPC-built historical compiler
revisions:

| Revision point | Hello ELF |
| --- | ---: |
| First self-host baseline | 287 bytes |
| Early IR era | 325 bytes |
| Before managed strings | 385 bytes |
| Initial managed-string lifecycle (`1064989`) | 737 bytes |
| Managed COW + concatenation (`dfc630a`) | 1,134 bytes |

The managed-string expansion explains the latest size increase. The later
Variant managed-string slice did not increase plain hello-world output.

## Root Cause

`ParseProgram` currently emits startup support eagerly:

- Heap BSS slots and Linux arena initialization are reserved unconditionally.
- `EmitAnsiStringRuntime` emits allocation/from-literal, retain, release,
  copy-on-write uniqueness, and concatenation helpers unconditionally.
- Initial stack preservation is emitted even when argv access is unused.

This was a reasonable implementation shortcut while the managed runtime was
moving quickly. It is not a required ABI or backend property.

## Rainy-Afternoon Cleanup

Add a lightweight feature-reachability pass before program emission:

1. Scan the parsed program and included units for required runtime features.
2. Emit managed-string helpers only when managed strings are reachable.
3. Split the helper bundle so retain/release, allocation, COW, and concat emit
   only when their dependency closure requires them.
4. Initialize the heap only when allocation-capable features are reachable.
5. Preserve the initial stack pointer only when argv access is reachable.
6. Keep target-specific region hooks optional. Bare-metal targets should use a
   fixed arena or linker-defined memory region without Linux `mmap`.

A coarse managed-string gate should reduce current hello from 1,134 bytes to
about 385 bytes. Gating heap startup and argv preservation should bring it
close to the actual body-plus-ELF floor.

## Embedded Interpretation

This audit is good news for future small targets: generated-code size has not
grown because the compiler architecture inherently requires a large runtime.
The emitter already writes compact native binaries directly. It merely needs
feature accounting before emitting optional support routines.

Do this when embedded backend work becomes active or when code-size tuning is
otherwise worth an afternoon. It does not block Nil Python, containers,
modules, SQLite, async groundwork, or the current allocator refactor.
