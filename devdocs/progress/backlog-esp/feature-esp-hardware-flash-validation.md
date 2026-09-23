---
slug: feature-esp-hardware-flash-validation
track: S
type: feature
prio: 25
status: backlog
owner: ""
created: 2026-06-30
blocked-by: []
summary: "HARDWARE-GATED AND NOT WORK ANYONE CAN PICK UP TODAY -- the prio is 25 for that reason and NOT because the ticket is unimportant. It is the row that decides whether the ESP work pays: two of the fleet's open technical claims live here and neither can be closed without a board on USB. (1) UART: tools/esp_flash.sh gained a --project pass/hang verdict (7d4f7ea33) and all four NilPy demos are OK in qemu against pin v413 -- but the log filter was written against QEMU output, so a filter tuned to qemu can strip a line a physical part prints and report a clean pass, which is this ticket's own first acceptance row failing silently. ONE INSTANCE OF THAT IS NOW FIXED AND THE ROW IS NOT CLOSED (2026-09-24, frankS): the filter dropped `^[IWE] (nnn)` and that class includes E, IDF's ERROR prefix, so a capture carrying a task-watchdog trigger and a corrupt-heap report -- a hung ISR and an allocation inside a handler, i.e. row 2's entire subject -- came out clean and the verdict printed OK, reproduced end to end. Both copies (tools/esp_flash.sh and examples/esp32/nilpy-c3/build.sh) now scan for E lines BEFORE the strip and fail naming them, outside the --project and --verify conditions because the ISR step runs --no-verify and compares nothing; esp_flash.sh also gained the reboot check its sibling already had. W only reports, deliberately: zero E and zero W measured in a real Espressif-qemu boot of the nilpy-c3 image (59 lines, 46 I-lines, app_main reached, so logging was live enough to show them) and the real harness still passes at HEAD, but that is QEMU and silicon may warn routinely. WHAT REMAINS FOR THE BOARD is unchanged and is the actual row: whether the filter matches what a physical part emits. This removed one way for the validation to lie; it validated nothing against silicon. (2) ISR: the acceptance asks that a peripheral/ISR FIRE, and firing is necessary and not sufficient -- boxing ALLOCATES, an allocation inside an interrupt handler faults later on another context's heap, and every timing number in between is correct because the timing IS correct. A run printing tick=1..5 status=0 satisfies the row as written and says nothing about the contract; what settles it is an assertion on the ALLOCATOR (allocation count unchanged across N ticks), a different assertion class from expect_same. THE CONDITION THAT SHOULD MOVE THIS PRIO is a board existing on the box -- the owner said 2026-09-20 that ESP32 is priority and that he will try to set hardware up later; until then a high rank would send seats to work they cannot start. Raise it the day silicon arrives, not before. WHY VISIBLE-BUT-LOW BEATS HIDDEN, and this is the argument that survives someone disagreeing about how likely a misdispatch is: THE TWO FAILURES HAVE DIFFERENT HALF-LIVES. Unpickability is short-lived and SELF-RESOLVING -- the moment a board exists the objection evaporates on its own. Invisibility is not: a ticket nobody can see stays unseen after the condition lifts, and the lifting event produces no notification. So the asymmetry favours ranked-and-low even if the misdispatch risk were higher than it is. AND NOT blocked/: that folder's convention is ticket-to-ticket via `blocked-by:` (sampled 3 of 3), and "no board exists on this box" names no ticket; rainy-day/ fits the deferral but is unranked and unscanned, which trades a small failure for the larger one. frankS holds both claims and can close neither."
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
calls.) That satisfies the acceptance's "a basic peripheral/ISR fires" — the
callback is dispatched by the SDK's timer interrupt, which is the real thing on
silicon and only emulated in qemu. `make test-esp-idf` guards the qemu side.

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
