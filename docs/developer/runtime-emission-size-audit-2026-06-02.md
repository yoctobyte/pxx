# Runtime Emission Size Audit - 2026-06-02

This is a dated rainy-afternoon note. The coarse Pascal runtime gate landed in
`1f9739a`; finer helper-level reachability remains deferred.

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

Before `1f9739a`, `ParseProgram` emitted startup support eagerly:

- Heap BSS slots and Linux arena initialization were reserved unconditionally.
- `EmitAnsiStringRuntime` emitted allocation/from-literal, retain, release,
  copy-on-write uniqueness, and concatenation helpers unconditionally.
- Initial stack preservation is still emitted even when argv access is unused.

This was a reasonable implementation shortcut while the managed runtime was
moving quickly. It is not a required ABI or backend property.

## Why Eager Emission Existed

The current Pascal pipeline parses declarations and bodies while emitting
machine code. Managed-value lowering emits direct calls to helper addresses
such as `AnsiStrReleaseAddr`. Emitting the complete helper bundle before
parsing user bodies made those addresses immediately available and kept the
one-pass parser simple.

That was a sequencing convenience, not a semantic requirement. It traded a
small Linux binary-size regression for easier runtime bring-up while managed
strings, arrays, and Variants were changing rapidly.

## Landed Gate Behavior

Commit `1f9739a` adds `DetectPascalRuntimeNeeds`, a conservative token pre-scan
before Pascal program emission:

- Clearly allocation-free Pascal programs skip Linux heap arena startup.
- They also skip the complete managed-string helper bundle.
- Programs keep heap startup when tokens indicate arrays, classes, raw memory
  operations, `New`, `Dispose`, `ReallocMem`, or `SetLength`.
- Programs keep managed-string support when managed-string mode, `AnsiString`,
  `Variant`, or imported units may require it.
- Imported units are treated as opaque and retain support. False positives are
  acceptable; false negatives are not.
- Nil Python remains eager for now because its dynamic fallback makes the
  narrowest safe gate less obvious.

This restores compact output without restructuring the parser or introducing
helper-call fixups. `make test` asserts that plain Pascal hello remains exactly
287 bytes.

## Why This Matters

Linux barely notices an extra kilobyte. Future microcontroller targets do.
ESP32-class boards, Arduino-class systems, and especially smaller PIC-class
devices benefit from emitting only the runtime capabilities a program reaches:

- smaller flash images;
- lower startup cost;
- no accidental dependence on unavailable hosted syscalls;
- a clearer path to fixed-arena bare-metal profiles;
- confidence that adding a high-level language feature does not tax unrelated
  tiny programs.

The direct emitter is already a good fit for this. Optional feature accounting
is enough; no runtime architecture rewrite is implied.

## Rainy-Afternoon Cleanup

The first coarse feature-reachability pass now scans Pascal tokens and omits
both heap startup and the managed-string bundle for clearly allocation-free
programs. Plain hello returned from 1,134 bytes to 287 bytes.

Remaining cleanup:

1. Split the helper bundle so retain/release, allocation, COW, and concat emit
   only when their dependency closure requires them.
2. Preserve the initial stack pointer only when argv access is reachable.
3. Apply an appropriate gate to Nil Python once its fallback requirements are
   clear.
4. Keep target-specific region hooks optional. Bare-metal targets should use a
   fixed arena or linker-defined memory region without Linux `mmap`.

A future precise gate may collect feature bits while parsing and emit helpers
after analysis, or use fixups for helper calls whose addresses are not known
yet. Either approach would reduce conservative false positives while
preserving the simple direct-emission model.

The landed coarse gate removes 847 bytes (74.7%). Gating argv preservation can
trim the remaining startup bytes later.

## Embedded Interpretation

This audit is good news for future small targets: generated-code size has not
grown because the compiler architecture inherently requires a large runtime.
The emitter already writes compact native binaries directly. It merely needs
feature accounting before emitting optional support routines.

Do this when embedded backend work becomes active or when code-size tuning is
otherwise worth an afternoon. It does not block Nil Python, containers,
modules, SQLite, async groundwork, or the current allocator refactor.
