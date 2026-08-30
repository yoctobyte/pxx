# PXX → ESP-IDF GPIO probe (ESP32-C3)

**This is a probe, not a demo.** It exists to answer one question that decides
whether slice 2 of `feature-esp-peripheral-callback-api` (the GPIO edge-callback
API) can be *witnessed* on this box: does Espressif's QEMU deliver GPIO edge
interrupts?

Measured 2026-08-30: **no — and not for the reason you would guess.**

```
PROBE: gpio_config rc=0
PROBE: install_isr_service rc=0
PROBE: isr_handler_add rc=0
PROBE: set 1 -> read 0
PROBE: set 0 -> read 0
   ... (5 toggles)
PROBE: pullup-input pin4 cfg rc=0 reads 0 (1 on real silicon)
PROBE: edges=0
PROBE: VERDICT qemu-delivers-NO-gpio-edges
```

**All three SDK calls return `rc=0`.** `gpio_config`, `gpio_install_isr_service`
and `gpio_isr_handler_add` all report success, and nothing whatsoever happens. A
probe that checked only return codes would have concluded GPIO works and gone on
to write a library against it.

**The control arm is what identifies the limit.** The first version only toggled
an `INPUT_OUTPUT` pin and counted ISR entries; `edges=0` is consistent with two
very different worlds — "GPIO works but interrupts are unmodelled" and "GPIO is
inert". So the probe also configures a *different* pin as `INPUT` with a
pull-up, which reads **1** on real silicon with nothing attached. It reads 0.

So QEMU's esp32c3 does not model the GPIO **input path** at all. The missing
edges are a consequence of that, not a separate gap — and no amount of
cleverness with edge types, ISR flags or pin choice will work around it, which
is precisely what you would otherwise spend a day discovering.

## Consequence for slice 2

The GPIO callback API cannot be accepted here. Writing it would mean shipping
code nobody has executed, which `feature-esp-peripheral-callback-api` explicitly
forbids — the same rule that kept it in `blocked/` twice. It needs a board.

Note this is a *measured* limit with a control arm, unlike the "no QEMU on this
box" claim that blocked the same ticket for five weeks and was never true.

## Running it

```bash
. ~/esp/esp-idf/export.sh
./build.sh              # build only
./build.sh qemu-assert  # build, boot, assert the CURRENT behaviour
```

`qemu-assert` asserts a **limit**, so a failure here is news rather than a
regression: either QEMU gained a GPIO model, or you are on real hardware — where
`edges>0` is the right answer and slice 2 just became acceptable. Read the diff
before updating the expectation.

## ADC (slice 3): measured too, and it fails DIFFERENTLY

Probed rather than inferred from the GPIO result, because "the GPIO peripheral
is unmodelled, so the ADC probably is too" is the kind of reasoning this ticket
family keeps punishing. It is not the same failure.

`adc_oneshot_new_unit` **never returns** under QEMU on esp32c3. The image does
not reach `app_main` at all: boot proceeds normally and stops at

```
W (408) eFuse: calibration efuse version does not match, set default version to 0
```

with no further output. Not a wrong value, not an error code — a hang inside the
first ADC call, before any of the probe's own output.

**Control:** the same project with `esp_adc` still in `REQUIRES` (so linked) but
the GPIO probe body running instead reaches `app_main` and completes normally.
So merely linking `esp_adc` is harmless; the hang is in the call. Without that
arm "the ADC image hangs" would have been indistinguishable from "adding the
esp_adc component breaks the build", which is a different bug with a different
owner.

Likely related to the ADC calibration fuses, which are burned on real parts and
absent from QEMU's default efuse blob — but that is a hypothesis, not something
this probe established, and it should not be written down as a cause.

So slice 3 is blocked on hardware as well, for its own measured reason.
