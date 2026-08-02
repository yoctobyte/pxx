# PXX ESP32-S3 esptimer demo (Xtensa / windowed)

`examples/esp32/timer-c3` compiled for the other ISA. The source is
byte-identical except for the program name: the point is that the event surface
(`TimerInit` / `OnElapsed` / `TimerStartPeriodicMs`) and a callback taken with
`@` are ABI-portable — nothing in `main.pas` knows which chip it is on.

```sh
. ~/esp/esp-idf/export.sh
make compiler/pascal26
cd examples/esp32/timer-s3
PXX=../../../compiler/pascal26 ./build.sh        # or ./build.sh qemu
```

Expected serial output after the IDF banner:

```text
PXX timer: started
PXX timer: tick=1
...
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```

## It does not do that today — and neither does the C3 original

Both chips currently report `done ticks=0 status=2`: the callback is never
dispatched, although `esp_timer_create` and `esp_timer_start_periodic` both
return `ESP_OK` and `esp_timer_is_active` says the timer is armed. It is
**layout-sensitive** — adding one unrelated statement to `app_main` makes it
fire 30 times out of 30 — so it is not this project and not the wrapper.

Tracked, with the full measurement chain and the hypotheses already killed, in
`devdocs/progress/urgent/bug-esp-timer-callback-never-dispatched.md`. This
project builds and links correctly; keep it as the xtensa half of the retest
once that bug is fixed.
