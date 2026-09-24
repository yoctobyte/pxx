---
prio: 30
track: B+S
type: feature
status: open
found: 2026-08-30
found-by: pxx-b
summary: "SLICE 2 (GPIO edges) LANDED AND RAN ON AN ESP32-S3 BOARD, 2026-09-24: lib/rtl/platform/esp/espgpio.pas arms a pin (on_rising / on_falling / on_change / edge_off) and its ISR calls only interrupts.IntPush; the handler is registered with interrupts.on_event and runs in the main task at a blocking point. examples/esp32/gpio-edge-s3 matches its spec on silicon: ordering (10 ISR entries, 0 delivered before a blocking point), count (ISR entries == delivered + dropped, including a 100-edge flood into the 64-slot ring), and two controls (an unarmed toggled pin and a disarmed pin add 0 ISR entries). The edge is a pin in INPUT_OUTPUT mode, whose pad feeds its own input, so no jumper and no human. The C3 build compiles and links but no C3 board was attached, so it is unrun. The ring fix that came with it is MEASURED under a concurrent producer (test/esp_board_gpio_ring_stress.pas): the new ring is exact over ~672k edges, twice; the old ring loses 2,503 and misorders 3,667. SLICE 3 (ADC conversion-done callback) REMAINS and is no longer blocked on hardware now that a board exists; under qemu adc_oneshot_new_unit never returns. The owner's hidden loop is a follow-on in feature-s-interrupt-events-reach-python-outside-interrupt-context."
---

## 2026-09-24 -- slice 2 done on a board (frankH)

The acceptance is the one in feature-s-interrupt-events-reach-python-outside-interrupt-context
(ordering and count), not "the callback fired". `tools/esp_flash.sh --project
examples/esp32/gpio-edge-s3` gives `OK -- board output matches main.expected (15 lines)`.

The first cut of interrupts.pas derived the slot a push fills as Head+Count and
decremented Count with a plain load/subtract/store. Both are wrong once the
producer is an ISR that can pre-empt the consumer. An edge landing inside
IntNext is either lost from the count or written one slot past the tail. Fixed
in the same commit: a producer-owned tail index and an atomic count. The gpio-edge-s3
run does not exercise that window, because every edge in it is made by the
consumer task. test/esp_board_gpio_ring_stress.pas does: a task pinned to core
1 toggles the pin while the main task on core 0 drains, for 20 s. MEASURED the
same day. The new ring is exact twice (671,997 ISR entries == delivered +
dropped, 0 out-of-sequence). The old ring under the same producer loses 2,503
edges from the accounting and delivers 3,667 out of sequence.

# ESP peripheral callback API — GPIO (slice 2) and ADC (slice 3)

Split out of [[feature-esp-peripheral-callback-api]] on 2026-08-30, when that
ticket's only defined acceptance — slice 1, the timer — was met and executed
under QEMU for the first time since it was written on 2026-07-11.

Slices 2 and 3 remain. Both are **blocked on hardware**, and unlike the block
that held the parent ticket for five weeks, both are measured with a control arm.

## Slice 2 — GPIO edge callbacks

`examples/esp32/gpio-c3` is the probe, landed with its result.

```
PROBE: gpio_config rc=0
PROBE: install_isr_service rc=0
PROBE: isr_handler_add rc=0
PROBE: set 1 -> read 0        (x5 toggles)
PROBE: pullup-input pin4 cfg rc=0 reads 0 (1 on real silicon)
PROBE: edges=0
```

All three SDK calls return **rc=0** and nothing happens.

**Control:** a second pin configured INPUT with a pull-up reads 0, where real
silicon reads 1 with nothing attached. So QEMU does not model the GPIO **input
path**; the absent edges follow from that rather than being a separate missing
interrupt model. That distinction is the whole value of the arm — the two worlds
have different workarounds, and only one of them has any workaround at all.

## Slice 3 — ADC conversion-done callback

Probed rather than inferred from slice 2. It fails differently.

`adc_oneshot_new_unit` **never returns**. The image does not reach `app_main`;
boot stops at `W (408) eFuse: calibration efuse version does not match, set
default version to 0` with no further output.

**Control:** the same project with `esp_adc` still linked (`REQUIRES esp_adc`)
but running the GPIO probe body instead reaches `app_main` and completes. So
linking the component is harmless and the hang is in the call — not "adding
esp_adc breaks the build", which would be a different bug with a different owner.

A plausible cause is the ADC calibration fuses, burned on real parts and absent
from QEMU's default efuse blob. **That is a hypothesis and is not established
here.** Do not record it as the cause without measuring it.

## Why this is blocked and not merely low prio

The parent ticket's standing rule is that writing more of it "would add code
nobody has ever executed". Both remaining slices have "the callback fires" as
their acceptance, and neither callback can fire on this box. A compile-and-link
check would pass on both and prove nothing — that is the trap the parent ticket
already names.

## What unblocks it

A C3/S3 board. `ls /dev/ttyUSB* /dev/ttyACM*` is empty as of 2026-08-30.

QEMU gaining a GPIO input model would unblock slice 2 alone.
`examples/esp32/gpio-c3/build.sh qemu-assert` asserts the CURRENT behaviour, so
it FAILS the day either happens, and says so in its failure text rather than
looking like a regression. That is the tripwire; nobody has to remember to
re-check.

## What NOT to do

Do not re-derive either measurement with a `command -v` style probe. The parent
ticket sat in `blocked/` twice on `command -v qemu-system-riscv32` returning
nothing, which was true and meant nothing: IDF installs its tools off PATH under
`~/.espressif/tools/`, reachable only once `export.sh` is sourced. Probe for a
tool where its installer puts it.
