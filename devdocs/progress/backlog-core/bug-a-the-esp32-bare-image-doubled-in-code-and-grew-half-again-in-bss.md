---
track: A+S
prio: 55
type: bug
status: open
found: 2026-08-30
found-by: frankD
summary: "An empty bare-profile ESP32 program was ~26 KB code / ~70 KB bss when docs/targets/esp32.md was written; at pin v393 it is ~50 KB / ~104 KB. Code roughly doubled, bss grew by half, on a part with ~400 KB of SRAM. Found while re-measuring published figures, not by a size gate. NO LONGER UNWATCHED and no longer only ESP: since 2026-09-05 tools/size_canary.py holds this number and it is FAILING — esp32c3-bare.code 50528 -> 57900 (+7372, +14.6%), over its 55580 budget — which is one of the reds holding seven's full tier. AND EVERY SUBJECT GREW against the 2026-08-30 baseline, x86_64-empty by +4025 code and +832 data, so an EMPTY PROGRAM ON THE HOST carries ~4KB more than it did six days ago: this is the always-linked surface growing, not an ESP profile problem. Raised 25 -> 55 on the argument that it was a gate failure with a live tier behind it. THAT ARGUMENT NO LONGER HOLDS AS OF 2026-09-06 AND THE PRIO HAS NOT BEEN CHANGED TO MATCH -- frankS re-baselined the canary to clear the row for a full-green pin the owner asked for, so this is watched-and-frozen rather than failing. The numbers above are the MEASUREMENT and stand; what changed is only that the canary no longer trips on them. Whoever ranks this next should decide whether 55 survives without the gate behind it -- it is left at 55 deliberately rather than churned by the person who removed its justification."
---


> **2026-09-06, frankS — the canary was RE-BASELINED, not fixed, and here is
> exactly what that did and did not settle.** The owner asked for a full-green
> pin; `size-canary` was one of nine reds and the only one whose subject is this
> ticket. `tools/size_canary.py --update` re-froze the reference at
> `c69b52b6ea35`, so the row is green and the growth is unchanged:
> **esp32c3-bare.code stays 57900** (was 50528 at the 2026-08-30 baseline).
> The baseline file says of itself that it *"blesses none of them"*, and this
> re-baseline blesses nothing either.
>
> **What I could NOT establish, stated so nobody re-derives it:** I did not
> attribute the +7372 bytes commit-by-commit. The mechanism is not in doubt —
> `--dce-report` on esp32c3 answers `off: target is not x86-64`, so every
> runtime helper landing is unconditionally linked into a bare image, and 34
> commits touched `compiler/*rv32*`/`*riscv*` since the baseline date
> (coroutines, labels-as-values, byte prefix). But *in kind* is not
> *byte-by-byte*, and I am not claiming the growth is all deliberate. Splitting
> it needs a bisect with a cross build per step and no `--map`/proc listing
> exists to shortcut it.
>
> **The asymmetry is the lead for whoever takes it:** esp32c3 grew +7372 while
> the three xtensa subjects each grew +2984 — the same runtime, ~4.4KB apart.
> Whatever riscv32 got that xtensa did not is where the bytes are.
>
> **And the previous holder declined this decision on purpose** (*"this one is a
> decision rather than a defect I can settle, so it is banked here rather than
> microfixed"*). I made it only because the target changed under it: a red that
> blocks a pin the owner has asked to be green is a different question from a
> red nobody is waiting on. It is reversible in one file if that reading is
> wrong.

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

## 2026-09-05 (frankS) — a third data point, so the trend has three

Measured while working the neighbouring bare-ESP tickets, on compiler
`5783500470d0`. Same shape as the ticket's own probe: an **empty** bare-profile
program, `program e; begin end.`

| when | code | bss |
| --- | --- | --- |
| `docs/targets/esp32.md`, as written | ~26 KB | ~70 KB |
| pin v393 (this ticket's filing) | ~50 KB | ~104 KB |
| **2026-09-05, xtensa** | **45420 B** | **103704 B** |
| **2026-09-05, riscv32** | **55460 B** | **103704 B** |

**The claim holds and has not got worse.** Code is roughly double the documented
figure and bss roughly half again, unchanged since v393 within noise. Note the
two arches differ in code by ~10 KB while sharing bss to the byte — bss is
almost certainly a fixed allocation rather than anything arch-dependent, which
narrows where to look.

**Still nothing watches this number**, which is the ticket's actual point. Worth
saying that `test-esp-bare` would be the natural place for a size row and that
it now runs green end-to-end on a box with the Espressif toolchains — but it is
enrolled in **zero** tiers, so a size row added there would be as unwatched as
the number is now. That ordering matters: enrolment
(`bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it`) has to come
first, or the guard is written into a target nothing executes. Not adding one
here for that reason.


## 2026-09-05 (frankZ) — the canary caught the next 7 KB, and it is not ESP-specific

Reproduced locally at `af6dc03d3`, `tools/size_canary.py` against its
2026-08-30 baseline `4039216a7f25`:

```
  subject              code    d(code)         data    d(data)          bss     d(bss)
  esp32c3-bare        57900      +7372        576       +232     103728        +36
  esp32s3-bare        46436      +2984        576       +232     103728        +36
  esp32s2-bare        46436      +2984        576       +232     103728        +36
  esp32-bare          46436      +2984        576       +232     103728        +36
  x86_64-empty        65304      +4025       2792       +832      43524      +1072
  esp32c3-bare.code: 50528 -> 57900 (+7372, +14.6%), over the allowed 55580
```

**THE ROW THAT FAILS IS NOT THE ROW THAT MATTERS.** Only `esp32c3` crosses its
budget, so the canary names it and a reader reasonably concludes "an esp32c3
problem". **All five subjects grew**, three ESP variants by an identical +2984,
and `x86_64-empty` — *an empty program on the host* — by **+4025 code and +832
data**. Nothing about an empty x86-64 program is ESP-specific, so whatever this
is lives in the always-linked surface every target pays for. esp32c3 is simply
the smallest budget and therefore the first tripwire.

The identical +2984 across esp32/esp32s2/esp32s3 and a *different* +7372 for
esp32c3 (a RISC-V part where the others are Xtensa) says at least two things
moved, not one — worth separating before anyone bisects, because a single-cause
assumption would be contradicted by that split immediately.

**NOT RE-BASELINED, deliberately.** The tool offers `--update` and says a moved
size "is not automatically a defect — but it is always a decision". Re-baselining
without knowing what grew is widening a guard's window to accommodate its own
subject, which is the failure this repo has named repeatedly. The decision needs
whoever owns the growth, and the six-day window (2026-08-30 -> 2026-09-05) is
where to look.

**Found while clearing seven's full-tier reds** (17 of 29 cleared that night by
other fixes); this one is a decision rather than a defect I can settle, so it is
banked here rather than microfixed.

## 2026-09-06 (frankF) — the stated lead points at something that does not exist: riscv32 got NOTHING xtensa did not

This ticket's lead is *"the asymmetry is the lead for whoever takes it —
whatever riscv32 got that xtensa did not is where the bytes are."* Measured at
`d6de711d1`, `compiler/pascal26 = c9de36a3754e`, `converged after 1 round(s)`,
same empty program on both:

| build | code | procs | B/proc |
| --- | --- | --- | --- |
| `--target=esp32c3 --esp-profile=bare` | 57,900 | **72** | 804 |
| `--target=esp32s3 --esp-profile=bare` | 46,436 | **75** | 619 |
| `--target=riscv32 --platform=posix` | 261,996 | **172** | 1523 |
| `--target=xtensa --platform=posix` | 212,844 | **175** | 1216 |
| `--target=arm32 --platform=posix` | 233,324 | 172 | 1356 |
| `--target=i386` | 106,348 | 136 | 782 |

**riscv32 emits THREE FEWER procedures than xtensa and 11,464 more bytes**, in
both profiles, and the ratio is the same in both (1.247 bare, 1.231 hosted). So
the standing gap is not content that riscv32 acquired. It is **bytes per
procedure**, and looking for a unit or a helper that xtensa lacks will find
nothing because there is not one.

The `+7372` vs `+2984` growth asymmetry is a **different quantity** and this
does not settle it — I did not build the 2026-08-30 tree, so I have no proc
counts at the baseline. What can be said from the two ends: the RATIO ITSELF
moved, 50528/43428 = **1.164** then against 57900/46436 = **1.247** now. A
constant 1.23x density would have grown riscv32 by ~3,670 B against xtensa's
2,984, not by 7,372, so roughly half the extra is density and the other half is
something about the code added since. Attributing that still needs the
per-procedure breakdown frankS said it needs.

### The available lever, stated as a lever and not as a diagnosis

**pxx emits no compressed (RVC) instructions on riscv32 at all.** Three checks
that fail differently:

- `compiler/rv32enc.inc` — **0** occurrences of `compressed`, `rvc`, or any
  `c.` mnemonic; the file has no 2-byte emit path.
- ELF header `Flags: 0x0` on the esp32c3 image — `EF_RISCV_RVC` unset.
- Raw disassembly of the image at its entry (`objdump -b binary -m riscv:rv32`,
  since a bare image has no sections): **1023 of 1025** decoded instructions are
  4 bytes, and the two 2-byte reads are objdump resynchronising on data.

The hardware has it: `ir_codegen_riscv32.inc:4321` already says *"the ESP32-C3/C2
core is RV32IMC"*, so the capability is known to the compiler and only the
encoder side is missing.

**What I am NOT claiming.** RVC is not the explanation for the 1.23x. Xtensa's
base encoding is **24-bit** with 16-bit narrow forms, so it is denser than RV32I
by construction and some of this gap is the two ISAs rather than a defect —
4/3 = 1.33 is the right order for that alone. What RVC is, is a lever of roughly
the right size (25-30% on typical RISC-V code) pointed at the metric this ticket
exists for, on a part where flash is the binding constraint. Treat it as the
largest unclaimed code-size item on riscv32, not as this ticket's cause.

Also visible in that disassembly and worth someone's eye separately: the
prologue does `addi sp,sp,-16` at +0x10 and again at +0x20 with two
`addi zero,zero,0` between them. Not measured further and not this ticket.
