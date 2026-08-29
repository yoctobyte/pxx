---
track: A+S
prio: 25
type: bug
status: open
found: 2026-08-30
found-by: frankD
summary: "An empty bare-profile ESP32 program was ~26 KB code / ~70 KB bss when docs/targets/esp32.md was written; at pin v393 it is ~50 KB / ~104 KB. Code roughly doubled, bss grew by half, on a part with ~400 KB of SRAM. Found while re-measuring published figures, not by a size gate — nothing watches this number."
---

# The ESP32 bare image doubled in code and grew half again in bss

Found re-measuring the numbers in `docs/targets/esp32.md` (Track D). **Not
fixed here** — the docs now state the measured values with the pin behind them;
this is the code-side ticket.

## Measured

Empty program, `--esp-profile=bare`, pinned **v393**, 2026-08-30:

| target | code | data | bss | published figure |
| --- | --- | --- | --- | --- |
| esp32c3 (riscv32) | **50,528 B** | 344 B | **103,692 B** | ~26 KB / 48 B / ~70 KB |
| esp32s3 (xtensa) | **43,428 B** | 344 B | **103,692 B** | ~21 KB / 48 B / ~70 KB |

```sh
printf 'program e;\nbegin\nend.\n' > empty.pas
pxx --target=esp32c3 --esp-profile=bare empty.pas out
```

`uses softfloat` adds **~64 KB** on riscv32 and **~54 KB** on xtensa (published
as ~50 KB, so that one is roughly right on xtensa and low on riscv32).

## Why it matters on this part specifically

An ESP32-C3 has roughly 400 KB of usable SRAM. A **103.7 KB** bss floor is about
a quarter of it before the program allocates anything or the stack is counted.
The page previously claimed "well under a quarter", which is no longer true —
that claim is now corrected, but the underlying growth is the real item.

The fixed 64 KiB heap arena is deliberate and accounted for. The remainder has
gone from ~6 KB to **~40 KB**, and that is the part nobody chose.

## What this is and is not

Probably the same root as
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]] — reachability-gated
emission not reaching what its title implies — which is why this is filed at the
same priority rather than higher. It is filed **separately** because that ticket
is about a hosted x86-64 hello-world and mentions neither ESP nor bss, and the
bss half is a different quantity from the code half: on a 400 KB part the static
arena and the globals are the binding constraint, not the text size.

**The finding underneath both is that nothing watches this number.** It moved by
2x with no test failing, and it was caught only because a docs page happened to
quote it and someone re-measured. A size canary on the bare profile — assert an
upper bound, fail when it moves — would have turned this into a one-line red on
the commit that caused it instead of a four-month drift found by prose.

## Gate

Whatever fixes it takes A's gate. For the canary, if anyone wants it: Track T.
