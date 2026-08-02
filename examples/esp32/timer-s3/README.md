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

It does — verified under qemu on 2026-08-02, and this is the first time the
xtensa half ever has. It did not until that afternoon: a 64-bit argument to a C
function was passed with only its low word, so `esp_timer_start_periodic`'s
period arrived with a stale pointer in its high half and the alarm was set some
145,000 years out. Both backends were affected; the write-up is
`devdocs/progress/urgent/bug-esp-timer-callback-never-dispatched.md`.

`make test-esp-idf` now guards both chips against a repeat.
