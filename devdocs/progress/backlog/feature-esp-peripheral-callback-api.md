---
prio: 53  # auto
---

# ESP32 peripheral callback API (timer / GPIO / ADC) — the user-facing "interrupt"

- **Type:** feature (library / Track B)
- **Status:** backlog
- **Owner:** opus-night
- **Opened:** 2026-06-21 (out of the ISR layering discussion; see
  `feature-esp32-isr-iram` for why the `interrupt;` *keyword* is NOT this)
- **Track:** B — `lib/rtl` / `lib/pcl`, built with `$(PXX_STABLE)`, no compiler
  rebuild.
- **Depends on (all DONE on Track A — compiler plumbing is complete):**
  - `iram;` IRAM placement (`.iram1.text`).
  - `@proc` / `@isr` proc-address fixups in `--emit-obj` `.o`
    (`writeELF32RelIram`, `R_*_32` vs the proc symbol).
  - `esp_intr_alloc` / esp_timer external C calls (extern C ABI).

## Why

From a *user's* perspective a timer / ADC / GPIO callback **is** "an interrupt",
even though at the ISA level it is a plain C callback dispatched by FreeRTOS
(which already did the window spill / context save before calling it). Users want:

```pascal
Timer1.OnElapsed := @MyHandler;        // or  Gpio.OnEdge := @h;  /  Adc.OnReady := @h;
```

They do **not** want to write `esp_intr_alloc(source, flags, @h, arg, @handle)` +
`cdecl; iram;` boilerplate, and they must **not** reach for the `interrupt;`
keyword — that is bare-metal raw-vector plumbing (see `feature-esp32-isr-iram`;
on IDF it actively breaks, because registering a raw-vector proc with
`esp_intr_alloc` double-saves context and `rfe`s instead of `ret`s → crash).

This ticket builds the high-level layer that hides the SDK call **and** the
`iram;` detail behind an event-style surface.

## Layering (keep the dark CPU magic hidden)

| Layer | Who | Surface |
|---|---|---|
| App user | "run my code when the peripheral fires" | `Timer1.OnElapsed := @h` |
| **This library** | wraps the SDK | `esp_intr_alloc` / esp_timer + callback trampoline marked `iram;` |
| Compiler (Track A) | plumbing | `iram;`, `@isr`, extern C — **all done** |

## Scope

- A peripheral unit (under `lib/rtl/.../esp` or `lib/pcl`) exposing callback
  registration for, in priority order:
  1. **Timer** (slice 1 — the proof). Start with **`esp_timer`** (the friendly
     option: runs the callback from a high-prio task, not a true ISR → no IRAM /
     ISR-safety restrictions, simplest correct slice). Optionally a true hw
     timer-group ISR variant later for hard-real-time.
  2. **GPIO** edge/level interrupt (`gpio_install_isr_service` + `gpio_isr_handler_add`).
  3. **ADC** continuous-mode "conversion done" callback.
- Callback type: a user-provided `procedure(arg: pointer); cdecl;`. For the true-ISR
  paths the library marks the registered trampoline `iram;` and passes `@cb` to
  the SDK; for `esp_timer` no IRAM needed.
- **Sane defaults** for flags / interrupt level / source so the user passes none
  in the common case.
- Document the **handler-safety contract** for the true-ISR variants (ISR context:
  no blocking, IRAM-safe APIs only, keep short, defer real work to a task).

## Non-goals

- The `interrupt;` keyword (raw hardware vector) — separate, **done**, bare-metal
  only. This library is the IDF/SDK path and never emits `interrupt;`.
- FreeRTOS task-notification / deferred-work framework beyond documenting the
  "ISR sets a flag / gives a semaphore, task does the work" pattern (possible
  follow-up).
- Compile-time enforcement of ISR-safe API restrictions.

## Open questions

- **API idiom:** property `OnElapsed := @h` (TNotifyEvent-style, matches existing
  pcl event surface) vs explicit `RegisterHandler(@h)`. Match whatever the
  current pcl/stdctrls event idiom is.
- **esp_timer vs hw timer group** for slice 1: `esp_timer` is os-timer (task
  callback, NOT a true ISR) — simplest and safest, but not hard-real-time;
  document that. Timer-group is a true ISR (needs `iram;` cb). Recommend
  `esp_timer` for slice 1, timer-group as a follow-up slice.

## Acceptance (slice 1 — timer)

- Example app: configure a periodic timer, callback increments a counter /
  toggles a GPIO / prints, runs under qemu IDF and matches the expected sequence.
- **No `esp_intr_alloc` / `iram;` / `esp_timer_*` visible in the example's app
  code** — only the library's event surface.

## Log

- 2026-07-11 (opus-night, slice 1) — **esptimer library + demo landed;
  runtime blocked on a Track A heap bug.**
  - `lib/rtl/platform/esp/esptimer.pas`: event-style surface over esp_timer
    (`TEspTimer` record, `OnElapsed := @h`, `TimerStartPeriodicMs` /
    `TimerStartOnceMs` / `TimerStop` / `TimerDone`); user callback signature =
    esp_timer_cb_t shape, registered directly (no trampoline needed for the
    task-dispatch path). No esp_timer_create args / esp_intr_alloc / iram in
    the app surface.
  - `examples/esp32/timer-c3/`: full IDF project (build.sh uses
    $(PXX_STABLE), --platform=esp, -Fu lib paths). Links green via
    `add_prebuilt_library(... REQUIRES esp_timer)` (plain
    target_link_libraries orderings leave esp_timer_* unresolved — CMake
    dedups the group). `app_main present in image map`.
  - lib-test gains a compile smoke: the example compiles to a riscv32 .o and
    imports esp_timer_create/start_periodic/stop/delete (readelf -sW).
  - **Blockers filed:**
    - [[bug-esp-emit-obj-proc-fixup-non-iram]] (Track A) — plain @proc in a
      relocatable .o errors ("@proc fixups need an iram/interrupt routine");
      the demo callback carries an interim `iram;` with a pointer to the
      ticket.
    - [[bug-esp-idf-heap-linux-mmap-ecall]] (Track A, prio 60) — the builtin
      heap on the IDF profile still linux-mmaps (PXX_ESP arena is keyed to
      PXX_ESP_BARE only), so the first string literal (PXXStrFromLit) panics
      under qemu ("Environment call from M-mode", MEPC=HeapMmap,
      RA=PXXAlloc, A7=222). Diagnosed to the exact define at
      builtinheap.pas:10-11; fix direction in the ticket (IDF profile ->
      malloc externals; hosted riscv32 keeps mmap; bare keeps arena). NOTE:
      this means hello-c3 also crashes if rebuilt today.
  - Parked (-> unfinished) until the heap ticket lands; then: qemu acceptance
    run, drop the interim iram;, then GPIO (slice 2) and ADC (slice 3).
- 2026-07-12 — **ESP work parked by user decision: Pascal has prio.** The ESP
  ticket family (this, the heap-mmap bug, the non-iram @proc fixup, the fd
  semantics follow-up) is deprioritized until Pascal/compat work settles.
- 2026-07-16 — requeued unfinished/ -> backlog/. Both Track A blockers now
  DONE (bug-esp-idf-heap-linux-mmap-ecall, bug-esp-emit-obj-proc-fixup-non-iram),
  so the technical park is cleared; remaining is low-prio Track B work (qemu
  acceptance run, drop the interim `iram;`, then GPIO/ADC slices). Stays low
  prio per the user's "Pascal has prio" call — no live agent, so out of the
  unfinished/ live-lock.
