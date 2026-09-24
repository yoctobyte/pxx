---
slug: perf-n-iterating-a-variant-list-costs-a-third-of-a-millisecond-per-element-on-esp32s3
track: N
tags: [S]
type: perf
prio: 30
status: low-prio
owner: ""
created: 2026-09-24
found-by: frankH (examples/esp32/adc-s3)
blocked-by: []
summary: "NOT A PATHOLOGY, measured 2026-09-24 on the ESP32-S3 board at compiler 58412e442c17: no step in the loop is a cliff. It is several ordinary factors multiplied together, and the list and iterator are not among them. A plain module-level `while j < n: tot = tot + j` costs the same ~550 us/iter as `for v in lst`. The factors: (1) the S3 demo projects run at IDF's default 160 MHz, not 240 (CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ), an available 1.5x; (2) NilPy on ANY 32-bit target is 4-5x slower than on x86-64, measured on the same host (i386: for-in 1.98 us/elem vs 0.47); (3) the xtensa backend emits spill-every-value stack code with inline literal pools, so a Pascal `x := x + i` loop body is ~40 instructions and 64 cycles/iter, and an empty call costs ~75 cycles; (4) the Variant work itself (a Pascal Variant add is ~2,500 cycles on the S3 vs ~300 on x86-64). The ~500x slowdown vs x86-64 is 28x clock times 4-5x word size times ~4x in-order code quality. Parked in low-prio under the owner's licence: ESP Python need not be maximally fast. Reopen if a single operation turns out to cost far more than its peers on the board, i.e. an outlier against the per-op table in the body."
---

# Iterating a Variant list costs ~330 us per element on an ESP32-S3

## Measured 2026-09-24, S3 board, probe compiled through examples/esp32/adc-s3's recipe

```
fps-window-ms 1004 frames 314      # 20 kHz, 64-sample frames: rate is right
50 reads ms 293 samples 3200       # adc.read() alone: ~6 ms per 64 samples
50 reads+sum ms 1330               # plus `for v in s: tot = tot + v`
```

(1330 - 293) / 3200 = 0.32 ms per element. The probe's source is below. It
uses time.monotonic, which works on ESP only since the same day's fix.

```python
a = ms(); tot = 0; k = 0
while k < 50:
    s = adc.read()
    for v in s:
        tot = tot + v
    k = k + 1
b = ms()
```

## 2026-09-24 (frankH): where the time goes. It is not a pathology.

All board figures are ESP32-S3 at **160 MHz** (read with `esp_clk_cpu_freq`; the summary above used to say 240, which was wrong). Compiler 58412e442c17. Probes ran through `examples/esp32/adc-s3` with `PXX_MAIN=`, timed with esp_timer.

**NilPy loops, us per element or iteration** (population: one 64-element list of ints built in Python, 1,280 steps):

| shape | S3 | x86-64 host | i386, same host |
| --- | --- | --- | --- |
| module `for v in lst: tot = tot + v` | 267 | 0.47 | 1.98 |
| same, inside a `def` | 382 | 0.90 | 3.05 |
| module `while j < 64: tot = tot + j`, no list | 529-547 | 0.48-0.52 | 2.31 |

The loop with no list costs as much as the one that iterates the list, so neither the list nor the iterator is the cost. The earlier "592 us/iter" plain-loop figure is this same row.

**Pascal micro-benchmarks, S3 vs x86-64** (2,000 or 100,000 iterations):

| operation | S3 | S3 cycles | x86-64 |
| --- | --- | --- | --- |
| `x := x + i`, locals | 399 ns | 64 | ~3 ns |
| same, globals | 591 ns | 95 | |
| empty procedure call | 440-475 ns | 70-76 | 4 ns |
| PXXVarRetain (int, a no-op) | 1276 ns | 204 | 14 ns |
| PXXVarBinOp, int + int | 5198 ns | 830 | 33 ns |
| PXXVarBinOpPas | 8927 ns | 1430 | 79 ns |
| `d := v + w`, Variants | 10848 ns | 1740 | 46 ns |
| `d := i` (box an int) | 5226 ns | 836 | 6 ns |

The S3 costs about 5-10x more cycles than x86-64 at every level, from a bare loop up to a Variant add. No row stands out from its neighbours.

**Why a bare loop costs 64 cycles.** Here is the disassembly of `for i := 1 to 100000 do x := x + i` with locals (`LocalLoop` in the probe). Every value is stored to the frame and reloaded. Int64 widening is done inline with a sign-fill branch. The loop bound is loaded through an inline literal pool that the code jumps over. The body comes to ~40 instructions per iteration. That is the xtensa backend's code quality, the same on every program. It is not a runtime slow path.

**What is not the cause** (each ruled out by a measurement above):
- the Variant list or the iteration protocol: the no-list loop is no faster;
- per-element allocation, a lock or PSRAM: the Pascal `x := x + i` loop has none of them and is already 64 cycles;
- an ESP-only runtime hook at loop back-edges: the same NilPy source on i386 shows the same shape, just 4-5x slower than x86-64.

**What would actually buy speed**, cheapest first:
1. Build the S3 demos at 240 MHz (`CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_240=y` in sdkconfig.defaults) for 1.5x. Not flipped here, because it is a power and thermal choice per demo, not a fix.
2. Register allocation or literal hoisting in the xtensa backend (Track A, O-tag). It would help every xtensa program, not just Python.
3. Cheaper Variant arithmetic on 32-bit targets; the i386 row shows the 4-5x is not ESP-specific.
