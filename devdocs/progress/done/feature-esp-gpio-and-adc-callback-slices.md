---
prio: 30
track: B+S
type: feature
status: done
found: 2026-08-30
found-by: pxx-b
summary: "DONE 2026-09-24, both slices run on an ESP32-S3 board through the interrupts pump (the ISR or driver callback only counts and calls IntPush; Python drains in the main task). SLICE 2 GPIO: espgpio.pas on_rising/on_falling/on_change/edge_off; examples/esp32/gpio-edge-s3 passes ordering, count and two controls (15/15 lines). Its ring fix is measured under a core-1 producer (test/esp_board_gpio_ring_stress.pas: exact over ~672k edges; the old ring loses 2,503). SLICE 3 ADC: lib/rtl/platform/esp/espadc.pas start/stop/read/frames/overflows/channel_pad; examples/esp32/adc-s3 passes ordering (frames arrive, 0 delivered before a blocking point), count (frames == delivered + dropped) and a value control on one pad (internal pull-up reads 3895, pull-down 363, of 4095) (7/7 lines). C3 variants of both build and link; no C3 board was attached, so they are unrun. Found and fixed on the way: time.sleep and time.monotonic did nothing on ESP (PalBackendNanosleep and PalBackendClockGetTime refused)."
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

## 2026-09-24 -- slice 3 done on a board (frankH)

`tools/esp_flash.sh --project examples/esp32/adc-s3` gives `OK -- board output
matches main.expected (7 lines)`. The driver's on_conv_done calls espadc's
handler, which counts and pushes (INT_SRC_ADC, channel). Samples come from
adc.read(), a non-blocking adc_continuous_read_parse, so the per-chip DMA
result bitfields are never mirrored.

Measured on the S3 at 20 kHz: 314 frames/s, one read() of 64 samples ~6 ms,
and summing those 64 in NilPy ~21 ms. That is why the demo's handler only
counts. See perf-n-iterating-a-variant-list-costs-a-third-of-a-millisecond-
per-element-on-esp32s3.

Three things found on the way:
- time.sleep() on ESP neither waited nor yielded, because PalBackendNanosleep
  returned unsupported. The first demo run was killed by the task watchdog.
  It now calls IDF's usleep.
- time.monotonic() returned 0.0 on ESP, because PalBackendClockGetTime
  refused every clock while PalBackendMonotonicMillis in the same unit
  already read esp_timer. The monotonic ids now read esp_timer; realtime
  still refuses.
- flush_pool is off. With it on, the driver's ISR receives from the ring
  buffer that read() receives from.
Unexplained, not chased: a debug loop printing each iteration lost 132 B of
heap per iteration. It was not isolated to any unit, and the shipped demo
does not have that loop.

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
