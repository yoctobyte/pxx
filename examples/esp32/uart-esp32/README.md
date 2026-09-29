# PXX classic-ESP32 UART1 test (Xtensa LX6)

`examples/esp32/uart-s3` on the third chip. The source is identical except for
the program name; only the build script differs, and only in the three places
every LX6 port differs (`--target=esp32` rather than
`--target=xtensa --xtensa-abi=windowed`, `xtensa-esp32-elf-ar`, and
`set-target esp32`).

`lib/rtl/platform/esp/espuart.pas` drives UART1, and the test checks it **with
nothing wired**, by two paths that bring what it sends back to its own receiver:

- **loopback** — the UART's internal TX→RX connection: the driver, the FIFO and
  the baud generator, but no pin.
- **one pad** — TX and RX both routed to `GPIO17`. The pad's output drives its
  own input, so the bytes leave through the GPIO matrix and come back through
  it: the path a real wire would use.

```sh
. ~/esp/esp-idf/export.sh
cd examples/esp32/uart-esp32
./build.sh
```

On a board, from the repo root:

```sh
tools/esp_flash.sh --project examples/esp32/uart-esp32 --port /dev/ttyUSB0
```

Each row prints `PASS` or `FAIL`; the last line is
`UART-CHECK-DONE passed=N failed=M`.

## Result on LX6 silicon: 10 of 13, and the shape of the three failures matters

Measured 2026-09-28 on an ESP32-D0WD-V3 over the CP2102, compiler
`b2b325036c3b`, one boot. `uart-s3` records 13 of 13 on the S3, so this is a
**chip difference, not a port mistake** — the Pascal source is identical.

```text
UART-CHECK on UART1, pad GPIO17
console refused PASS (0)     open PASS (0)          loopback on PASS (0)
loopback echo   FAIL (12)    available PASS (5)     drain PASS (5)
timeout empty   PASS (0)     timeout ms PASS (200)  fast echo FAIL (18)
pad open        PASS (0)     pad echo   PASS (11)   pad control FAIL (2)
closed          PASS (0)
UART-CHECK-DONE passed=10 failed=3
```

**Board output, not re-measured on v450.** Compiler `b2b325036c3b` is pin v448; no later
board run is recorded.

The detail in brackets is `Length(s)`, the number of bytes that came back, and
that is what makes the three failures readable rather than mysterious. `MSG` is
`'hello uart1'`, 11 bytes; the fast row expects `MSG + ' at 1M'`, 17.

| row | wanted | got | so |
| --- | --- | --- | --- |
| `loopback echo` | 11 | **12** | one extra byte |
| `fast echo` | 17 | **18** | one extra byte, at 1,000,000 baud too |
| `pad control` | **0** | 2 | two bytes arrived that should not exist |

So nothing is *missing* — one byte too many comes back on the internal-loopback
path, at both baud rates, and the control row that is supposed to see silence
sees two bytes.

### `pad echo` PASSES, and you should not trust it on this chip

This is the part worth reading twice. `pad control` exists precisely to prove
that `pad echo`'s bytes travelled out of GPIO17 and back in: it repeats the echo
with TX routed to a different pin, and passes only when **nothing** returns
(`Row('pad control', (rc = 0) and (s = ''), Length(s))`). Here it returned two
bytes. **A passing row whose control fails is not evidence**, so on the LX6 the
`pad echo` PASS does not establish that the GPIO matrix carried anything; it only
establishes that 11 correct bytes arrived by some path.

### A hypothesis, explicitly NOT established

All three failures are consistent with one cause: stale bytes left in the RX FIFO
between rows, which the rows then inherit — the checks run in sequence on one
port, so a leftover cascades, and "one byte too many" plus "two bytes where there
should be none" is what that looks like. That would make it a drain/flush
difference on this chip rather than three separate faults.

**This is a guess. It has not been tested, and it must not be written up as the
cause.** The cheap experiment is to run the echo rows in isolation, or to drain
explicitly before each, and see whether the extra byte survives. Nobody has done
that yet. LX6 is outside the settled S3/C3 scope, so it is recorded here rather
than fixed.

## Why there is no `main.expected` here

`timer-esp32` carries one, so this is a deliberate difference rather than an
omission. Each row prints a `detail` integer alongside its verdict, and for the
timeout row that detail is the **measured** milliseconds (the row passes
anywhere in 180..260). A whole-output diff would therefore fail on a healthy
board for a reason that has nothing to do with the UART, so the oracle would be
worse than none: it would train whoever meets it to ignore the tool. The verdict
is the `passed=`/`failed=` counts. `uart-s3` records its evidence the same way.

## The pad number is the thing most likely to need changing

`PAD = 17` is inherited from the S3. On the classic ESP32, GPIO17 is an ordinary
GPIO on a plain D0WD-V3 part — but on **WROVER** modules GPIO16 and GPIO17 are
wired to the PSRAM, so the pad rows there are testing a pin that is already
spoken for. If the two pad rows fail while the loopback rows pass, suspect the
board's module before suspecting `espuart`: that split is the signature, because
the loopback path never leaves the peripheral.

## Scope

The owner's settled ESP scope is the **S3 and C3**. The classic ESP32 is
**proven where run, not promised**; the chip each result was witnessed on is
recorded in the docs rather than implied.

## QEMU

This example needs a board: a classic ESP32 board, nothing wired. `build.sh` has no QEMU mode.
