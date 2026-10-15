# A bytecode VM for microcontrollers: wasm/WAMR or our own fat bytecode

_Findings and direction from a discussion with the owner, 2026-10-15. This is a
note, not a plan: nothing here is started, and nothing should be until the owner
picks it up._

## The idea

Two projects that go together:

1. **A VM** that runs on ESP (C3, S3, other ESP chips) and also builds for the PC.
2. **A pxx backend** that emits its bytecode.

**What it would buy:**
- **One artifact for many microcontrollers.** The same app runs on a C3 and an
  S3 today. Chips nothing has run on yet (C2, C6, H2, P4, the original ESP32,
  S2) would get it for free once the VM runs there.
- **Testing on a PC VM.** The app can be tested on a PC VM before it goes to a
  board.
- **Small app updates.** Updates of a few KB, possibly with no reboot. Today a
  thermostat image is ~640 KB.

What made this attractive: the S3 build of the thermostat is 2.4x the C3 build
(main build .text 226,591 vs 93,614 B), because all the 2026-10-14 size work
went into the riscv32 backend only. The Xtensa backend also emits no density
(2-byte) instructions, which leaves an estimated ~31 KB of S3 .text on the
table. Static RAM (.data/.bss) is byte-identical on both chips. A shared
bytecode would sidestep per-backend work for app code.

## Option A: wasm on WAMR. Doable, standard engine, too slow for us as an interpreter

pxx already has a wasm32 backend on master (`compiler/ir_codegen_wasm32.inc`,
WASI imports; background in `wasm-target-findings.md`). So the bytecode would be
standard wasm, and the PC side already works with any wasm runtime.

- **Engine:** WAMR (Bytecode Alliance) is the mature choice. Espressif packages
  it as an official ESP-IDF component, listing ESP32, C3, S3, C6, P4 and C5. It
  has interpreter, AOT and JIT modes, and AOT code can run from flash (XIP).
  wasm3 is a smaller interpreter, but it is in minimal maintenance mode.
- **Host API: not standardized.** WASI covers stdout, files and clocks, not
  GPIO, WiFi, sockets or HTTP. Espressif's esp-wasmachine and esp-wdf provide
  such bindings. They are Espressif-only and early-stage, and one has a build
  guide reported broken. We found no shipped product using them.
- **Real-world use on MCUs:** research benchmarks and prototypes, including
  WAMR vs wasm3 on an ESP32-C6, multi-app ESP32 deployment, and runtime rule
  updates. We found no named production deployment on a microcontroller.
- **RAM:** wasm memory comes in 64 KiB pages, and the pxx heap and shadow stack
  would live inside it. Two or three pages would take most of a C3's ~230 KB
  free heap. The custom-page-sizes proposal (pages as small as 1 byte) exists,
  but it is not settled across runtimes, and WAMR support is unconfirmed.

**The elephant is performance.** Wasm was designed as a compile target, for JIT
or AOT, not for interpretation. Its opcodes are thin (`i32.add`, `i32.load`), so
an interpreter pays dispatch overhead on every one. In wasm, the whole pxx RTL
(allocator, refcounting, AnsiString concat/copy/compare, IntToStr and other
formatting) would itself be interpreted. Rendering a web page is almost entirely
string and formatting work, so a 10-50x penalty there is not acceptable.

There are mitigations, each with a cost:
- **Import the hot RTL routines as native host functions.** WAMR lets natives
  work on linear memory in place. But every routine moved native becomes host
  API that has to be versioned.
- **Compile with WAMR AOT per chip** (`wamrc` on the PC, XIP from flash). This
  gives native speed, but one artifact per architecture again, which defeats
  the point.

## Option B: our own fat bytecode. Where performance points

The interpreters that serve web pages acceptably on an ESP32 (MicroPython, Lua,
Berry, Espruino) all use **fat opcodes**. One opcode, such as a string concat,
is one dispatch followed by a native C routine that does all the work. The
interpreted part is only the glue between native calls.

This fits pxx naturally:
- **The IR already has fat string operations.** String concat, compare, assign
  and the scope-exit releases are distinct IR nodes, not loops (see
  `ir-as-substrate.md`). A bytecode can be a compact serialization of the IR,
  and the VM an IR interpreter whose string and format ops call native RTL
  routines.
- **The native layer is the RTL we already have.** The routines behind the fat
  opcodes would be the existing pxx RTL (`builtinheap` etc.), compiled natively
  for each chip and for the PC. One source on every side.

The cost: it's a custom format with no standard behind it, and we build and
maintain the VM ourselves. That is what the MicroPython, Lua and Berry projects
did, for the same reason.

**Direction, per the owner:** WAMR support is doable but carries a severe
performance hit, which may or may not be acceptable per app, and the wasm-on-MCU
stack is not standardized. For performance, we are back to our own fat bytecode.

## Design notes that hold for either option

**Two layers of OTA.** The firmware (VM plus native bindings) and the app
(bytecode) update separately:
- **Firmware** uses today's mechanism: `ota_0`/`ota_1` slots, bootloader trial
  and rollback, reboot.
- **App** uses its own A/B pair of data partitions, read in place with
  `esp_partition_mmap` (no RAM copy). It has its own trial and rollback record,
  for example in NVS, and switches with a VM restart instead of a reboot.
- **The OTA receiver lives in the firmware, never in the app,** so a broken app
  cannot block its own replacement.
- **Version the host API explicitly,** and check the version before switching
  app slots. New firmware may only add imports, never change or remove them.
  Update firmware first, then apps.

**Brain-to-relay propagation** works per layer. With one bytecode for every chip,
a C3 brain could update an S3 relay's app. The current native images cannot do
that.

**RAM stays first** (owner, 2026-10-12). Code and bytecode belong in flash,
memory-mapped. The VM's own working RAM is the number to measure before
committing to a design.

## Cheapest next experiments, when the budget allows

1. Dump the thermostat's IR and estimate its size as a naive fat bytecode. That
   checks the density argument against today's 94 KB (C3) and 227 KB (S3) of
   .text.
2. Compile the thermostat with `--target=wasm32` and read the `.wasm` size and
   its declared linear-memory pages. That gives the wasm RAM cost.
3. Read esp-wasmachine's native-extension headers, to see what a real ESP host
   API looks like before designing ours.

## Sources (web, 2026-10-15; not all verified page by page)

**WAMR:**
- ESP-IDF component: https://components.espressif.com/components/espressif/wasm-micro-runtime
- XIP: https://raw.githubusercontent.com/bytecodealliance/wasm-micro-runtime/main/doc/xip.md
- Zephyr module: https://docs.zephyrproject.org/latest/develop/manifest/external/wamr.html

**Espressif wasm frameworks:**
- esp-wasmachine: https://github.com/espressif/esp-wasmachine/
- esp-wdf: https://github.com/espressif/esp-wdf/blob/master/README.md
- esp-wdf build report: https://esp32.com/viewtopic.php?p=145370

**wasm3:**
- https://github.com/wasm3/wasm3

**Small wasm pages:**
- Proposals list: https://github.com/webassembly/proposals
- LLVM support: https://llvm.googlesource.com/llvm-project/+/6018930ef1fa62315c3e02b8b8b775056bd5224d

**WAMR vs wasm3 on MCUs (incl. ESP32-C6):**
- https://arxiv.org/abs/2512.00035v1

**WAMR in Rust firmware (FOSDEM 2026):**
- https://fosdem.org/2026/schedule/event/rust-wasm-embedded

**ESP-IDF partitions and mmap:**
- https://docs.espressif.com/projects/esp-idf/en/v5.4/esp32c3/api-reference/storage/partition.html
