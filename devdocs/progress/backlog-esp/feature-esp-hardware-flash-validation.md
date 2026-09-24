---
slug: feature-esp-hardware-flash-validation
track: S
type: feature
prio: 25
status: backlog
owner: ""
created: 2026-06-30
blocked-by: []
summary: "S3 ROWS MET ON SILICON 2026-09-24 (frankH, ESP32-S3 devkit on /dev/ttyACM0, compiler 58412e442c17 unless noted). C3 AND S2 ROWS STAY OPEN: no C3 or S2 board is on this box, so this ticket stays open until one is. Per row, S3: (1) UART boot == oracle: MET, test/test_esp_hw_validation.pas via `esp_flash.sh --chip esp32s3` matches the x86-64 oracle 7/7. (1b) Does the filter match silicon: MET for the four S3 NilPy demos (nilpy-s3 and nilpy-hw-s3 with the pinned compiler, gpio-edge-s3 and adc-s3 with HEAD). The raw reset-capture minus IDF log lines equals main.expected line for line, 0 lines stripped after app_main, one boot each. Silicon prints ONE routine W that qemu does not, BEFORE app_main: `spi_flash: Detected size(16384k) larger than the size in the binary image header(4096k)`. The E scan has fired on silicon for a real task-watchdog trigger (the first adc-s3 run, before time.sleep was fixed). (2) ISR fires: MET, isrctx (built for esp32s3 from isrctx-c3's main.pas with ISR dispatch on) prints `isr hits=5 ctx=1` against `task hits=5 ctx=0`, PAIR OK; also the GPIO-edge and ADC-frame ISRs of examples/esp32/gpio-edge-s3 and adc-s3. (2b) The contract, no allocation in the handler: MET for espgpio's and espadc's handlers. test/esp_board_isr_no_alloc.pas shows a free-heap delta of 0 over 9,997 GPIO and 625 ADC ISR entries, heap integrity OK, idle drift 0. Readout control (-dALLOC_IN_TASK, 1000 x 16 B) reads 28,000, so the zeros are real. The ISR-allocating control (-dALLOC_IN_ISR) aborts on the FIRST entry with `pxx: out of memory (ESP-IDF heap exhausted)`: loud, but the message misnames the cause. Timer step (esp_timer, task dispatch, NOT an ISR): runs on silicon inside nilpy-hw-s3. OPEN: every C3 row (test_esp_hw_validation, nilpy-c3, nilpy-hw-c3, isrctx-c3 itself, gpio-edge-c3, adc-c3; all build) and every S2 row (hello-s2 builds with --target=esp32s2; atomics are refused on the S2 by design until feature-a-esp32s2-atomics-by-interrupt-masking)."
---

# ESP32 real-hardware flash + boot validation (S2/S3, C3)

- **Type:** feature (validation — requires physical hardware) — Track A
- **Status:** backlog (blocked on hardware access; un-automatable in-harness)
- **Opened:** 2026-06-30 (split from feature-esp32-idf-xtensa, whose QEMU scope is done)

## Scope

The ESP QEMU + GDB path is verified ([[feature-esp32-idf-xtensa]] done). What
remains can only be done with a board on USB:
- Flash a pxx-built ESP32-S2/S3 (Xtensa) + ESP32-C3 (riscv32) image to real silicon.
- Confirm UART boot output matches the QEMU/x86-64 oracle.
- Exercise a live ISR / peripheral (timer/GPIO) on hardware (the QEMU path can't
  install a real vector).

## Acceptance

A pxx ESP image boots on a physical board and its UART output matches the oracle;
a basic peripheral/ISR fires on hardware. Requires the user's board + USB access.


## Everything except the board is now in place (2026-08-02)

The three things that made this "un-automatable" are done; what is left is
literally plugging a board in.

### 1. One command flashes and checks

```sh
tools/esp_flash.sh [--chip esp32s2|esp32s3|esp32c3] [--port /dev/ttyUSB0] <prog.pas>
```

`tools/esp_flash.sh` is the silicon twin of `tools/esp_run.sh` — same projects,
same compiler flags, same output filter — so a program verified under qemu is
re-checked on hardware with one word changed. It compiles the program for the
chip, links it into the matching IDF project, writes flash with esptool, reads
the serial console for N seconds, and (by default) **diffs what the board said
against the same program run on x86-64**. It finds the port itself when exactly
one is present and refuses to guess between several.

### 2. A program worth running first

`test/test_esp_hw_validation.pas` — everything it prints is pure computation, so
board output must equal the x86-64 run byte for byte. It covers 64-bit
arithmetic, a by-value record result, a 9-word argument list (the two xtensa ABI
gaps closed this session), and managed strings; it toggles GPIO2 between lines
so an LED or a scope shows it is really executing.

Verified under qemu against the oracle on **esp32s3 (Xtensa/windowed)** and
**esp32c3 (riscv32)**. The S2 has no qemu machine, so its first run IS the
hardware run.

### 3. The S2 exists as a target at all

`examples/esp32/hello-s2` is new. The S2 was never built for before — every
project here was S3 or C3 — and it is half the user's hardware. It builds and
links a pxx `app_main` with `idf.py set-target esp32s2`; `esp_flash.sh --chip
esp32s2` uses it as the harness.

## Procedure for the board session

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26

# per board, one line each:
tools/esp_flash.sh --chip esp32s3 test/test_esp_hw_validation.pas
tools/esp_flash.sh --chip esp32s2 test/test_esp_hw_validation.pas
tools/esp_flash.sh --chip esp32c3 test/test_esp_hw_validation.pas
```

Expected: the seven lines below, then `esp_flash: OK — board output matches the
x86-64 oracle`, and an LED on GPIO2 that changed state a few times.

```text
pxx esp hw validation
pow3^20 3486784401
int64min+1 -9223372036854775807
divmod -9223344366821 -675344
vec 7000011 4199 120
string ABCDEFGH 8
ok
```

Things that are expected to bite, so they do not read as failures:

- **Download mode.** If esptool cannot open the chip, hold BOOT and tap RESET,
  then re-run. The script says so on failure.
- **Port permissions.** `/dev/ttyUSB0` needs the `dialout` group (log out and
  back in after adding yourself).
- **Which LED.** GPIO2 is the devkit LED on most S3/C3 boards; several S2 boards
  use GPIO15 or none. A missing LED changes nothing about the diff.
- **`--no-signals`.** Programs that pull the signal runtime must pass
  `ESP_PXXFLAGS="--no-signals"`; without it app_main panics on an `ecall` in its
  prologue. The validation program does not need it.

## The peripheral half is unblocked too (2026-08-02, later)

[[bug-esp-timer-callback-never-dispatched]] is FIXED — it was a 64-bit argument
to a C function being passed with only its low word, so `esp_timer`'s period
arrived with a stale pointer in its high half. Both chips now run the periodic
callback correctly, xtensa included. So the board session gets a second step:

```sh
ESP_PXXFLAGS="--no-signals -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp" \
  tools/esp_flash.sh --chip esp32s3 --no-verify --seconds 15 \
  examples/esp32/timer-c3/main/main.pas
```

Expected:

```text
PXX timer: started
PXX timer: tick=1 ... tick=5
PXX timer: done ticks=5 status=0
```

(`--no-verify` because the demo has no meaningful x86-64 run: it is all SDK
calls.) ~~That satisfies the acceptance's "a basic peripheral/ISR fires" — the
callback is dispatched by the SDK's timer interrupt, which is the real thing on
silicon and only emulated in qemu.~~ The esp-idf tier guards the qemu side.

> **THE STRUCK SENTENCE IS WRONG AND IT WOULD HAVE TICKED THE ISR BOX WITHOUT
> ENTERING AN ISR** (2026-09-24, frankS; board-independent, measured from source
> on this box). `timer-c3` goes through `lib/rtl/platform/esp/esptimer.pas`,
> which **hardcodes** `args.dispatch_method := ESP_TIMER_TASK` (line 141). IDF's
> own header defines that enumerator as *"Callback is dispatched from esp_timer
> **task**"* (`esp_timer.h:61`), against `ESP_TIMER_ISR` — *"dispatched from
> **interrupt handler**"* (`:63`). The SDK's timer interrupt fires and then
> **queues to the esp_timer task**; the pxx callback runs there. **No pxx code
> executes in interrupt context on this path, on silicon or in qemu.**
>
> The tree already disagreed with itself and the demo was the half that was
> right: `examples/esp32/timer-c3/main/main.pas` says in its own header
> *"esp_timer callbacks run in task context and need no IRAM placement"*. Two
> sources in the repo, opposite claims, and IDF's header settles it.
>
> **So the step is worth running and is not the ISR row.** What it establishes —
> a periodic callback is created, dispatched and returns correctly across both
> ISAs — is real and it is what the 2026-08-02 `esp_timer` fix was about. What it
> does NOT establish is anything about interrupt context, which means row 2's
> allocation hazard *cannot be triggered by this demo at all*: there is no
> handler for an allocation to happen inside of.
>
> **This is the ticket's own expected-value collision one level deeper.** The
> 2026-09-20 note asked *"if the machinery did nothing about allocation, would
> this row still pass?"* — yes. Add: it also passes if there is no interrupt
> context anywhere in the image, which is the case for this program.
>
> **THE PROGRAM THAT DOES EXERCISE IT ALREADY EXISTS**, and it belongs to
> `feature-n-a-non-allocating-restricted-thunk-for-an-isr`, not here:
> `examples/esp32/isrctx-c3` registers BOTH dispatch methods in ONE image and
> reports both, so the task arm reproduces the 0 and the ISR arm must not — the
> asymmetry is the result and neither half is a result alone. It is wired into
> the esp-idf tier (`Makefile:36597`, `build.sh qemu-assert`). **A board session
> should run that one for the ISR row**, and should expect
> `PXX isrctx: isr hits=5 ctx=1` with a NON-ZERO ctx; a `-1` means the callback
> never fired, which is why the sentinel is `-1` and not `0`.
>
> Not touched here and deliberately: that probe and the thunk question are
> frankb-8e's. This note corrects THIS ticket's procedure and nothing else.

Still worth watching on hardware: qemu's systimer is not the S2/S3 silicon's, so
a timer that works in emulation and not on the board would be new information.

## 2026-09-20 — two open claims attached here rather than filed separately (frankS)

Both belong to this ticket's existing acceptance rows and neither needs a page
of its own. Attaching the evidence to the ticket that already called it.

### 1. The UART verdict now has an instrument, and the instrument is unverified

`tools/esp_flash.sh` gained `--project`, `--no-flash`, chip inference, a
`main.expected` oracle and a `--project`-scoped IDF-log strip (`7d4f7ea33`), so
the four NilPy demos have a route to a board with a real pass/hang verdict
rather than a human reading scrollback. **Established before hardware: all four
are OK in qemu against pin v413.**

**WHAT IS NOT ESTABLISHED, AND IT IS THE WHOLE POINT OF THIS TICKET'S FIRST
ACCEPTANCE ROW:** whether the log filter matches what real silicon emits. The
filter was written against qemu output and the ROM/bootloader preamble differs
on a physical part. **A filter tuned to qemu can strip a line the board prints
and report a clean pass**, which is the failure this ticket exists to catch, so
do not read the qemu greens as evidence about it. **The board is the only
instrument**; say which one, and which chip, beside the first green.

### 2. "A basic peripheral/ISR fires" IS A ROW THAT PASSES WHILE THE CONTRACT IS VIOLATED

The acceptance above asks that an ISR *fire*. **Firing is necessary and is not
sufficient, and the gap is not cosmetic.** The callback-ABI work has three
consumers; frankb-8e took two and deliberately left ESP interrupts, because the
contract there genuinely differs: **boxing ALLOCATES, and an allocation inside
an interrupt handler is a latent crash with good latency numbers.** It does not
fault on the tick that allocates. It faults later, somewhere else, on a heap
another context was using — and every timing number collected in between looks
correct, because the timing IS correct.

**So a hardware run that prints `tick=1 … tick=5` and `done ticks=5 status=0`
satisfies the row as written and says nothing about the contract.** This is the
expected-value collision in this ticket's own acceptance: *if the machinery did
nothing about allocation at all, would this row still pass?* Yes, every time.

**The condition that springs it** is any callback path reaching an ISR context
through a boxed value — not any particular demo, which is why this is stated as
a mechanism rather than as a row that fires today. **What would settle it** is
an assertion that observes the allocator rather than the output: a run with the
ESP heap instrumented across the handler, asserting the allocation count is
UNCHANGED across N ticks. That is a different assertion class from `expect_same`
and cannot be reached by strengthening the tick comparison, in the same way a
leak cannot fail a value check.

**Ownership:** frankS holds this question and cannot close it — there is no
board on this box, so it is the same honest kind of open as row 1. Not going
near the ESP consumer of the callback ABI until there is silicon; no collision
with 8e in either direction, confirmed through the coordinator.

## 2026-09-24 — row 1's instrument had a silent-pass mechanism, and it is closed (frankS)

**This does NOT close row 1 and the prio does not move.** Row 1 asks whether the
filter matches what real silicon emits, and that is still a question only a board
answers. What is closed is a *specific, host-side, board-independent* defect in
the instrument — one that would have made the board session report a clean pass
over exactly the failure the ticket's OTHER row exists to catch.

### The defect, reproduced before it was fixed

The `--project` log filter drops `^[IWE] \([0-9]+\) ` — IDF's log format. That
class includes **`E`, the error prefix**. Fed this capture:

```text
Calling app_main()
PXX timer: started
PXX timer: tick=1
PXX timer: tick=2
E (5123) task_wdt: Task watchdog got triggered. The following tasks did not reset the watchdog in time:
E (5123) task_wdt:  - IDLE0 (CPU 0)
W (5123) heap_init: corrupt heap detected at 0x3fca1234
PXX timer: tick=3
```

the filter emits a clean, contiguous `tick=1 … tick=3`, and the verdict logic
prints **`OK — board output matches (4 lines)`**. Measured end to end, not
inferred from the regex.

**The two swallowed lines are the ones this ticket is about.** A task-watchdog
trigger is what a hung ISR looks like. `corrupt heap detected` is how an
allocation inside an interrupt handler surfaces — row 2's entire subject. **The
instrument built to validate the ISR contract was deleting the evidence for it.**

### Why nothing caught it

The filter was never wrong about what it was asked to do: strip IDF's chatter so
a capture compares against an oracle written without it. It is the third rule in
CLAUDE.md's instrument section — *correct about something else*. And the two
places it lives had drifted: `examples/esp32/nilpy-c3/build.sh` asserts
`boots == 1`, catching a panic-reboot loop; `tools/esp_flash.sh` asserted
nothing. Same guard, present in one of the two places that need it.

### What changed

Both copies now scan the capture for `E (nnn)` lines **before** the strip, and
fail naming them. `tools/esp_flash.sh` also gained the reboot check (bound at
`>= 2`, not `== 1`, because esptool's hard reset races the reader there and a
missing banner is ordinary). The scan runs **outside** the `--project` and
`--verify` conditions on purpose: **this ticket's own ISR step runs with
`--no-verify`**, so it performs no comparison at all and an error line was
otherwise unreported by anything.

`W` lines report but do not fail — see the target note below.

### Which target each number came from

- **The defect and both fixes are host-side shell logic**, reproduced on a
  synthetic capture. No board involved and none needed.
- **Not born red — measured, not assumed.** A real boot of this repo's
  `examples/esp32/nilpy-c3` image under **Espressif qemu, esp32c3**: 59 lines,
  **zero `E`, zero `W`**, 46 `I` lines and `Calling app_main()` present — so
  logging was demonstrably live at a level that would have shown them. (A zero
  from a dead boot looks identical to a real zero; that is why the `I` count and
  the program's own output are quoted beside it.) Then the **real harness**,
  rebuilt at HEAD with the guard in place: `OK nilpy-c3 … one boot`.
- **That measurement is QEMU and the target that matters here is SILICON.** A
  physical part's bootloader may warn routinely where qemu does not, which is why
  `W` is advisory and only `E` fails. **If the first board run reports warnings,
  that is expected and is information — say which chip, and whether a `W` line
  ever appears on silicon during a passing run.**
- The system `qemu-system-riscv32` **cannot** run these images (`unsupported
  machine type: "esp32c3"`); the Espressif fork under `~/.espressif/tools` is the
  one that can. Two qemus, and only one of them answers.

### What the board session should now expect

The procedure above is unchanged. What is different is that a run which prints
the right lines while the chip is failing underneath will now say so instead of
printing OK. That does not validate the filter against silicon — it removes one
way for the validation to lie.

## 2026-09-24 -- the S3 rows, on silicon (frankH)

Board: ESP32-S3 devkit, 16 MB flash, /dev/ttyACM0. Every row below ran on it.

**Row 1, UART == oracle.** `tools/esp_flash.sh --chip esp32s3
test/test_esp_hw_validation.pas`: `OK -- board output matches the x86-64 oracle
(7 lines)`.

**Row 1b, the filter against silicon.** For each project: the esp_flash
`--project` verdict, then a separate raw capture of the same image after an
RTS reset. The raw lines after `Calling app_main()`, minus `^[IWE] (nnn)`,
were compared with main.expected.

| project | compiler | verdict | raw == expected | stripped after app_main | boots |
| --- | --- | --- | --- | --- | --- |
| nilpy-s3 | pinned | OK (4) | yes | 0 | 1 |
| nilpy-hw-s3 | pinned | OK (8) | yes | 0 | 1 |
| gpio-edge-s3 | HEAD 58412e442c17 | OK (15) | yes | 0 | 1 |
| adc-s3 | HEAD 58412e442c17 | OK (7) | yes | 0 | 1 |

The one W line silicon prints is before app_main, in every boot:
`W (NNN) spi_flash: Detected size(16384k) larger than the size in the binary
image header(4096k).` It is the board's real flash size against the image's
declared 4 MB. It is harmless, and it answers the note above: yes, silicon
warns routinely where qemu did not, so W being advisory was the right call.

**Row 2, an ISR fires.** isrctx-c3's main.pas built for esp32s3: the build.sh
with `--target=esp32s3` and `set-target esp32s3`, the same
sdkconfig.defaults with ISR dispatch on, run via `esp_flash.sh --project`.
It printed `main ctx=0`, `task hits=5 ctx=0`, `isr hits=5 ctx=1` and `PAIR OK
status=0`. That twin project is not committed; isrctx is frankb-8e's example.

**Row 2b, the contract.** test/esp_board_isr_no_alloc.pas (the recipe is in
its header):

```
idle isrs=0    heap-delta=0     integrity=1
gpio isrs=9997 heap-delta=0     integrity=1     (espgpio edge ISR)
adc  isrs=625  heap-delta=0     integrity=1     (espadc conv-done ISR)
-dALLOC_IN_TASK: gpio heap-delta=28000          (readout sees 1000 x 16 B)
-dALLOC_IN_ISR:  aborts on the first entry, "pxx: out of memory (ESP-IDF
                 heap exhausted)", reboot loop
```

The ISR-allocation abort is useful (it is loud), but its text blames the heap
when the heap is not exhausted. Whoever owns the ISR thunk question
(feature-n-a-non-allocating-restricted-thunk-for-an-isr) may want the message
to say "allocation in interrupt context".
