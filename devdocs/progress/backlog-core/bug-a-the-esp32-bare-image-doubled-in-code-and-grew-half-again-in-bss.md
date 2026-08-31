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

---

## 2026-08-30 — the canary exists now (Track T). The size is still yours.

`tools/size_canary.py`, baseline in `tools/size_baseline.json`, wired into
`native` + `limited` + `full` as `size-canary#00`. **It freezes today's numbers;
it blesses none of them.** Everything above this line is still open.

What it does, and the two choices worth arguing with:

- **A delta gate, not a ceiling.** A ceiling needs a number a human must
  maintain and defend; a delta needs only the last measurement. Growth beyond
  the allowance is a red on the commit that grew it.
- **bss is watched tighter than code** — 5% / 2 KiB against 10% / 4 KiB —
  because of this ticket's own argument: on a ~400 KB part the bss floor is the
  binding constraint, not the text size. The allowance is the *larger* of the
  fraction and an absolute floor, so a 344 B metric is not tripped by rounding
  and a 50 KB one is not handed a free 4 KiB.
- **Advisory**, like `demos` and the FPC canary: twatch reports and tickets it,
  so the signal arrives, but it does not fail the tier's verdict. A ratchet that
  reds the whole fleet until someone re-baselines is a ratchet that gets
  switched off, and this repo has written that down twice.
- **It prints every measurement on every run**, pass or fail. Silence on a no-op
  is indistinguishable from silence on a never-ran, and the second is what this
  defect actually was.
- **Failing to MEASURE is a failure**: a compile that fails, a size line it
  cannot parse, or a subject with no baseline are all red, with the `--update`
  command in the message. A canary that reports no growth because it measured
  nothing looks exactly like the good news it is not.

Baseline as adopted (`4039216a7f25`, HEAD, which matches your v393 figures to
within 24 B on xtensa):

| subject | code | data | bss |
| --- | --- | --- | --- |
| esp32c3-bare | 50,528 | 344 | 103,692 |
| esp32s3-bare | 43,452 | 344 | 103,692 |
| esp32s2-bare | 43,452 | 344 | 103,692 |
| esp32-bare | 43,452 | 344 | 103,692 |
| x86_64-empty | 61,279 | 1,960 | 42,452 |

### One measurement that fell out of building it, for the sibling ticket

The last row is not padding. `x86_64-empty` is an **empty program** —
`program e; begin end.` — and it is **61,279 B of code**.
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]] is about a
*hello-world* at ~63 KB. So the hello is roughly **two kilobytes of program on
top of a sixty-one kilobyte floor**, and whatever reachability-gated emission is
failing to gate, it is not failing on anything the program wrote. That narrows
that ticket considerably and it is now watched too.

*(Track T built the instrument. Making the numbers smaller is A+S — and when
they do get smaller, the canary will say so out loud and ask to be
re-baselined, because a baseline left above a real shrink is slack the next
regression fits underneath.)*
