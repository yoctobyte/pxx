---
slug: perf-n-iterating-a-variant-list-costs-a-third-of-a-millisecond-per-element-on-esp32s3
track: N
tags: [S]
type: perf
prio: 30
status: open
owner: ""
created: 2026-09-24
found-by: frankH (examples/esp32/adc-s3)
blocked-by: []
summary: "On an ESP32-S3 board (240 MHz, compiler 5cb3fdf5896b + the espadc work), `for v in lst: tot = tot + v` over a 64-element list of ints returned from a Pascal unit (espadc.read(), a TPyList of Variants) costs ~21 ms, about 330 us per element, roughly 80,000 cycles for one add. Fetching the same list (a C driver call plus 64 appends) costs ~6 ms. So a Python handler that processes a 20 kHz ADC stream falls behind about 8x. Not measured: which part is slow (Variant boxing, list iteration protocol, int add on a Variant, or refcounting); whether a list built in Python iterates as slowly; the x86-64 figure for the same loop. Start with those three to find the mechanism."
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
