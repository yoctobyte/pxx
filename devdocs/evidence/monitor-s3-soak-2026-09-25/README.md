# monitor-s3 soak on an ESP32-S3, 2026-09-25

Raw evidence behind the showcase row in `docs/examples/index.md` ("A Python
sensor monitor on an ESP32-S3") and the soak figures in
`docs/getting-started/esp32.md`, `docs/library/esp.md` and the release notes.
It was captured by frankh-95 and copied here by frankD from a /tmp scratchpad
that is reaped after about 6 hours.

| file | what it is |
| --- | --- |
| `soak.raw` | Raw serial bytes read after a reset, 262 s, IDF boot lines included. Report lines start with `#`. |
| `monitor240.npy` | The program that produced `soak.raw`. |
| `run.sh` | The build, flash and capture commands. |
| `build.log` | The build and flash log. |
| `run.out` | The run's own summary: compiler, tree and report count. |
| `pin.raw`, `pinbuild.log` | A second, 51-report run, built by the example's own `build.sh`. **Neither the compiler nor the program is recorded**, so this run is not cited anywhere. |

**Provenance of `soak.raw`:** compiler sha256 `29956ba5beff`, tree `9c14efd7b`.
That is after pin v424. ESP-IDF v6.0.1. An ESP32-S3 at chip revision v0.2, on
a CH343 UART bridge at `/dev/ttyACM0`, CPU at 160 MHz. Capture started at
01:01 local time. The capture was a plain raw serial read after a reset
pulse; the reader is not in the repository.

**The program is not the checked-in `examples/esp32/monitor-s3/main/main.npy`.**
It differs in exactly three places, checked with `diff`:
- `REPORTS = 240` instead of 10;
- a `heap0` baseline taken before the loop;
- the older `done:` line (`heap change … bytes`).

The report lines have the same format. The capture window ended at report 193,
before the program finished, so there is no `done:` line.

**What the file shows**, re-derived by frankD from `soak.raw` (`tr -d '\r'`,
lines starting with `#`):
- 193 reports.
- Free heap only ever between 257,948 and 262,072 bytes: 48 readings at 2579xx,
  one at 258,084 (report 1) and 144 at 2620xx. Report 193 reads 257,968,
  inside that range. There is no drift.
- ADC mean 3858 to 3861, with nothing connected to GPIO 1.
- 16 frames per report.
