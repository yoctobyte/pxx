# nilpy includes anything from ESP-IDF and it just works

- **Type:** feature
- **Status:** backlog
- **Blocked-by:** feature-c-source-frontend, feature-esp32-idf-xtensa
- **Relation:** integration milestone, not new plumbing. The IDF *link/boot*
  mechanism is the esp32-idf tickets (done/feature-esp32-idf-riscv32 proved
  PXX→`.o`→IDF-link→boot on C3; feature-esp32-idf-xtensa does S2/S3). Those
  scope a *Pascal* `app_main` calling a *hand-bound* GPIO/UART/delay subset.
  This ticket is the north-star: **nilpy source** that `include`s **arbitrary**
  IDF headers and uses them, building on the C source frontend
  (feature-c-source-frontend) + that link plumbing. See
  devdocs/developer/frontends-and-targets-strategy.md (embedded north-star).

## The goal (one sentence)

Write an app in nilpy, `include` any ESP-IDF header, call what it declares,
build a target `.o`, let IDF link + flash — and it works — without hand-writing
bindings per API.

## The compile/link boundary (so scope is unambiguous)

```
nilpy app  ──┐
IDF headers ─┤  OUR COMPILER  ──►  main.o (relocatable xtensa/riscv32 ELF)
             │   • parse headers (decls, structs, macros, consts)            │
             │   • compile YOUR code → target machine code                   │
             │   • compile static-inline bodies you USED                     │
             │   • emit ABI calls + UNDEFINED refs for IDF extern symbols    ▼
             └─────────────────────────────────────────►  IDF TOOLCHAIN
                                                            • link .o + IDF .a
                                                            • linker script,
                                                              IRAM/DRAM place
                                                            • firmware + flash
```

- **OUR task:** emit a correct `.o`. We never compile IDF's `.c` (shipped
  precompiled in `.a`).
- **IDF's task:** link our `.o` against its `.a` + linker script → firmware.
- **The subtlety:** a `static inline` in a header looks like an extern but has
  **no symbol anywhere** (internal linkage) → WE must compile its body into our
  `.o`. This is why broad IDF consumption needs the C *body* frontend, not just
  declaration import.

## What this milestone needs (dependency chain, by symbol kind)

| IDF construct | requirement | where it lives |
| --- | --- | --- |
| extern function (in IDF `.a`) | ABI call + undefined ref | feature-esp32-idf-xtensa plumbing + existing FFI |
| **`static inline`** (HAL/LL: `*_ll.h`, `*_hal.h`) | **compile the body** | feature-c-source-frontend Slices A–C |
| **function-like macros** (`ESP_LOGI`, `BIT(x)`, `REG_WRITE`, `portTICK_PERIOD_MS`) | **expand + compile** | feature-c-source-frontend Slice E |
| **register structs** (`soc/*_reg.h`, `*_struct.h`: bitfields + volatile) | **honor packed/aligned/bitfield/volatile** | feature-c-source-frontend Slice F |
| struct/enum/`#define` consts | model layout + values | header import (mature) |
| **arbitrary header tree** (FreeRTOS + soc + hal + driver + esp_common, keyed on `sdkconfig.h`) | **robust import / graceful degrade** | new work — see below |
| **nilpy untyped surface** | **infer types from imported C signatures** | new work — see below |

The C-frontend slices **E, F, and A–C-for-static-inline are the IDF-critical
ones** (vs nice-to-have for desktop C). This ticket is the reason they matter.

## New work owned by THIS ticket (beyond the dependencies)

1. **IDF header-import robustness.** IDF's transitive `#include` tree is
   GTK-grade macro soup, gated on a Kconfig-generated `sdkconfig.h`. Need:
   include-path resolution into the IDF component tree, `sdkconfig.h` ingestion,
   and graceful-degrade (opaque fallback) on constructs we can't model **while
   still exposing the symbols/inlines actually called**. Reuse the GTK
   degrade-gracefully strategy (c-skipped-features-audit.md).
2. **nilpy FFI type inference.** nilpy is untyped at the surface; infer argument
   and result types from the imported C signatures so `gpio_set_level(pin, 1)`
   type-checks and lowers with the right ABI without a hand-written binding.
   Builds on the callee-return inference + auto string→`const char*` already
   landed (wrapper-free-c-from-nil-python.md); extend to IDF-shaped APIs.
3. **nilpy `app_main` entry** into the IDF component model (the existing IDF
   tickets wire a Pascal `app_main`; do the nilpy equivalent).

## Non-goals

- IDF link mechanism / linker script / boot — owned by feature-esp32-idf-xtensa
  (and the done riscv32 ticket). Not re-done here.
- Compiling IDF's own `.c` sources — they ship precompiled.
- A full C frontend — that's feature-c-source-frontend; this consumes it.
- C++-only IDF APIs (Arduino-core C++ classes) — separate C++-subset ticket.

## Acceptance

A nilpy program that `include`s an arbitrary IDF header (not a curated subset)
and:
- calls a **linked extern** driver function (resolved by IDF at link),
- calls a **`static inline` HAL** function (compiled into our `.o`),
- uses a **function-like macro** and a **register struct** field (bitfield /
  volatile),
builds to a target `.o`, IDF links it, and it runs on real ESP32-S3 (and C3 via
the done riscv32 path). Type-correct with **no hand-written per-API binding**.
Bonus / north-star: edit→build `.o`→IDF-link in the seconds range.

## Log
- 2026-06-17 — opened. Separated from the IDF link/boot tickets (those = Pascal
  + hand-bound subset + plumbing). This is the integration milestone: nilpy +
  arbitrary IDF header consumption. Clarified the compile/link boundary (our job
  = emit `.o`; IDF = link) and the `static inline` subtlety (no symbol → we
  compile it into our `.o`), which is why it depends on the C body frontend
  (Slices A–C static-inline, E macros, F register layout) rather than header
  import alone. New work owned here = IDF header-import robustness +
  `sdkconfig.h` + nilpy FFI type inference + nilpy `app_main` entry.
