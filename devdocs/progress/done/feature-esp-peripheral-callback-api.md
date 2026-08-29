---
prio: 30
---

# ESP32 peripheral callback API (timer / GPIO / ADC) — the user-facing "interrupt"

- **Type:** feature (library / Track B)
- **Status:** done
- **Owner:** pxx-b
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

## Moved to blocked/ (2026-07-20, Track B sweep)

Slice 1 (esptimer + demo) is written but **unverified**, and the acceptance for
every remaining slice is "it runs on the device". Neither ESP32 hardware nor a
qemu/IDF runner is available to this lane, so nothing here can be honestly
completed or honestly closed — it would be code nobody has ever executed.

Blocked on an external constraint, not on another ticket, which is what
`blocked/` is for (same category as [[feature-port-macos]]). What would unblock
it: a C3/S3 board or a working qemu-esp32 harness. A host-side compile-only
smoke (riscv32 `.o` + `readelf -sW` import assertions) is possible without
hardware and would be worth doing, but it proves linkage, not behaviour — do not
mistake it for acceptance.

## Back to blocked/ 2026-07-31 (Track B sweep) — still no way to RUN it

Re-checked rather than assumed: this box has no `qemu-system-riscv32` and no
`qemu-system-xtensa`, `IDF_PATH` is unset, and there is no board. An ESP-IDF
checkout exists at `~/esp/esp-idf`, which is enough to LINK and nothing more.

Every remaining item here — the qemu acceptance run, dropping the interim
`iram;`, and the GPIO and ADC slices — has "it runs on the target" as its
acceptance. Writing more of it would add code nobody has ever executed, which
is the one thing this ticket already says not to do.

**Tagged for later testing.** When a C3/S3 board or a working qemu-IDF harness
appears, the first action is the slice-1 acceptance run that was never done, not
more slices. The existing compile-only smoke in `lib-test` (riscv32 `.o` +
`readelf -sW` import assertions) stays where it is — it proves linkage, and it
must not be read as acceptance. Nothing further from this ticket goes into the
regression suite until something can execute it.

## 2026-08-30 (pxx-b) — THE BLOCK WAS FALSE. There is a working ESP QEMU on this box.

Re-checked before taking the ticket, and the answer is the opposite of what the
last two sweeps recorded. Both Espressif QEMU forks are installed, with the
toolchains, and they run:

```
~/.espressif/tools/qemu-riscv32/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-riscv32
    QEMU emulator version 9.2.2 (esp_develop_9.2.2_20250817)
    machines: esp32c3   Espressif ESP32-C3 machine
~/.espressif/tools/qemu-xtensa/esp_develop_9.2.2_20250817/qemu/bin/qemu-system-xtensa
    machines: esp32     Espressif ESP32 machine
              esp32s3   Espressif ESP32S3 machine
```

Plus `riscv32-esp-elf`, `xtensa-esp-elf`, both gdbs, `openocd-esp32`, and an
ESP-IDF **v6.0.1** checkout at `~/esp/esp-idf` with `export.sh`.

**Why two sweeps missed it, and this is the reusable part.** Both checks asked
`command -v qemu-system-riscv32` (the 2026-07-31 entry above says so in as many
words: *"this box has no `qemu-system-riscv32`"*). That is true and it is not
the question. IDF-managed tools are installed **off PATH by design**, under
`~/.espressif/tools/`, and only reach PATH when `. $IDF_PATH/export.sh` is
sourced. `IDF_PATH` is unset in a fresh shell, so the probe was structurally
incapable of seeing an installed runner — it tested the shell's environment and
reported it as a property of the machine.

Both sweeps wrote *"re-checked rather than assumed"*, and both were honest: the
command was really run and really returned nothing. **Running a check is not the
same as running a check that could have come back positive.** The instrument had
no true arm — the same failure this repo keeps meeting from other directions
(a guard that passes on the state it rejects; a probe whose two arms are
indistinguishable). The cost was a ticket family parked ~5 weeks on a fact that
was never true.

For the next reader: probe for a tool by looking where its installer puts it,
not by asking whether the current shell happens to have it. For IDF that is
`ls ~/.espressif/tools/`, or sourcing `export.sh` first.

Also stale in this file: the README's *"KNOWN BROKEN under qemu right now"*
points at `bug-esp-idf-heap-linux-mmap-ecall`, which the 2026-07-16 entry above
already records as DONE.

Same claim appears in `feature-dns-esp-backend`,
`feature-pal-esp-posix-fd-semantics`, and `feature-esp-hardware-flash-validation`
— none re-verified by me beyond noting they cite the same premise. The
hardware-flash one is genuinely blocked (no board: no `/dev/ttyUSB*`
or `/dev/ttyACM*`); QEMU does not unblock flashing to real silicon.

Next action per this ticket's own instruction is the slice-1 acceptance run that
was never done — NOT more slices.

## 2026-08-30 (pxx-b) — SLICE 1 ACCEPTANCE PASSED. First execution since 2026-07-11.

`examples/esp32/timer-c3` built under ESP-IDF v6.0.1 and booted on the emulated
C3. Serial:

```
I (414) main_task: Calling app_main()
PXX timer: started
PXX timer: tick=1
PXX timer: tick=2
PXX timer: tick=3
PXX timer: tick=4
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```

That satisfies this ticket's stated acceptance for slice 1: a periodic timer
configured through the library's event surface, the callback firing and counting,
matching the expected sequence under qemu IDF. The app-code check holds too --
`main.pas` names only `TimerInit` / `OnElapsed` / `TimerStartPeriodicMs` /
`TimerStop` / `TimerDone`; no `esp_timer_create`, no `esp_intr_alloc`, no `iram;`.
The interim `iram;` is already gone (both Track A blockers landed).

`status` is a bitmask the app builds itself (1 = start failed, 2 = fewer than
five ticks, 4 = stop failed), so `status=0` is not reachable by a dead timer.
That is the assertion; the exit code is not.

**Made repeatable:** `./build.sh qemu-assert` — drives qemu directly with serial
to a file, asserts the exact seven-line sequence, exits 77 with an explanation
naming the off-PATH trap when the emulator is absent. NOT wired into `lib-test`:
it needs `export.sh` sourced and takes minutes. Opt-in, documented in the README.

**Both arms verified** (pass on a real boot; skip-with-reason on a bogus
`QEMU_BIN`). Worth recording that the first two cuts of the script FAILED, and
both failed as an EMPTY CAPTURE rather than an error:

1. no flash image — `idf.py set-target` wipes `build/`, and my regeneration line
   was a stub that did nothing. qemu booted with no image and wrote an empty log.
2. an all-zero efuse block — reports chip revision v0.0 against an image
   requiring >= v0.3, so the bootloader rejected it and rebooted forever. 306KB
   of boot attempts, zero app lines.

Both are indistinguishable from "the program ran and printed nothing" if you
only look at the assertion result. The efuse defaults now come from IDF's own
`QEMU_TARGETS` table rather than a pasted constant. `set-target` is now guarded
so a re-run does not trigger a from-scratch 988-target rebuild.

**Boundary, stated precisely and written into build.sh and the README as well as
here:** a green run witnesses a genuine `esp_timer` callback dispatched by
FreeRTOS through the library's event surface on EMULATED silicon. It does not
witness real silicon, timing, the physical peripheral, anything analog, or
anything xtensa. Flashing to hardware remains genuinely blocked — no
`/dev/ttyUSB*` or `/dev/ttyACM*` — so `feature-esp-hardware-flash-validation`
is NOT unblocked by this.

Remaining in this ticket: GPIO (slice 2) and ADC (slice 3), both now genuinely
attemptable rather than blocked. Slice 1 is done and, for the first time,
executed.

## 2026-08-30 (pxx-b) — SLICE 2 (GPIO) CANNOT BE WITNESSED HERE. Measured, with a control.

Probed before writing any of it, because the ticket forbids adding code nobody
has executed and I wanted to know whether an acceptance was reachable at all.
`examples/esp32/gpio-c3` is that probe, landed with its result:

```
PROBE: gpio_config rc=0
PROBE: install_isr_service rc=0
PROBE: isr_handler_add rc=0
PROBE: set 1 -> read 0        (x5 toggles)
PROBE: pullup-input pin4 cfg rc=0 reads 0 (1 on real silicon)
PROBE: edges=0
PROBE: VERDICT qemu-delivers-NO-gpio-edges
```

**All three SDK calls return rc=0 and nothing happens.** A probe that checked
only return codes concludes GPIO works and writes a library against it.

**The control arm is what makes this a diagnosis rather than an observation.**
The first cut only toggled an INPUT_OUTPUT pin and counted ISR entries, and
`edges=0` is equally consistent with two different worlds: "GPIO works, the
interrupt model is missing" and "GPIO is inert". So the probe also configures a
SECOND pin as INPUT with a pull-up, which on real silicon reads 1 with nothing
attached. It reads 0.

So QEMU's esp32c3 does not model the GPIO **input path** at all. The missing
edges follow from that; they are not a separate gap. No choice of edge type, ISR
flag or pin works around it — which is the day this control arm saves.

**Disposition: slice 2 needs a board.** Writing the GPIO unit now would produce
exactly the unexecuted code this ticket has twice refused to accumulate. Note
the difference from the block this same ticket carried for five weeks: THAT one
was a probe with no true arm and was never true; this one is measured and has a
control. Both say "blocked"; only one of them earned it.

`./build.sh qemu-assert` in gpio-c3 asserts the CURRENT behaviour, so it fails
the day QEMU gains a GPIO model or the day someone runs it on hardware — where
edges>0 is the right answer and slice 2 becomes acceptable. The failure text
says so, to stop the next reader "fixing" it by updating the expectation.

**Slice 3 (ADC) is NOT measured.** Do not infer it from this — probe it the same
way. Reasoning from the GPIO result is the move this ticket keeps punishing.

State of the ticket: slice 1 done and executed; slices 2 and 3 blocked on
hardware, one measured and one unknown.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
