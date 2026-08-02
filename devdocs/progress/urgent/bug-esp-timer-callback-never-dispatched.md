---
track: A
prio: 70
type: bug
summary: "An esp_timer periodic callback never fires — on BOTH chips — although create/start return ESP_OK, the timer reports active, and the callback pointer handed to the SDK is provably correct. Adding ONE unrelated statement to app_main makes it fire 30/30. Layout-sensitive, so a codegen/emit-obj fault, not the timer wrapper."
---

# esp_timer callbacks are not dispatched — and one extra statement fixes it

- **Type:** bug (silent: no panic, no diagnostic, the callback simply never
  runs) — **Track A** (the layout sensitivity puts it below `lib/rtl`; the
  esptimer wrapper is exonerated below)
- **Found:** 2026-08-02, porting the esp_timer demo to xtensa for
  [[feature-esp-hardware-flash-validation]]
- **Blocks:** the peripheral/ISR half of ESP hardware validation — this is the
  one surface a user exercises first on a real board.

## Repro — two files that differ by ONE line

`devdocs/progress/fixtures/bug-esp-timer-callback-never-dispatched-A.pas` and
`...-C.pas`. The whole diff is a statement in `app_main` that only *prints* the
callback's address:

```pascal
  h := MakeTimer;
+ esp_rom_printf('cb=%x'#10, Integer(@OnTick));      { C only }
  rc := esp_timer_start_periodic(h, 100000);
```

Run either with:

```sh
ESP_RUN_TIMEOUT=25 ESP_PXXFLAGS="--no-signals" \
  tools/esp_run.sh --chip esp32c3 devdocs/progress/fixtures/bug-...-A.pas
```

| | A (as written) | C (one extra printf) |
| --- | --- | --- |
| `esp_timer_create` | rc=0 | rc=0 |
| `esp_timer_start_periodic` | rc=0 | rc=0 |
| ticks after ~3 s at 100 ms | **0** | **30** |

Deterministic — two runs each, same numbers. Same on esp32s3 (xtensa,
windowed): the stock `examples/esp32/timer-c3` demo reports
`done ticks=0 status=2` on **both** chips.

## What has been ruled out, by measurement

- **Not the callback pointer.** Printing `a.callback` from inside the creating
  function in the FAILING variant gives `420301b8` — the identical value the
  working variant prints. Both hand the SDK the same, correct address.
- **Not the timer wrapper (`lib/rtl/platform/esp/esptimer.pas`).** The repro
  declares `esp_timer_*` itself and builds the args record inline; no library
  code is involved.
- **Not a 64-bit-argument ABI misalignment.** The suspicion was that
  `esp_timer_start_periodic(handle, periodUs: Int64)` needs its 64-bit pair on
  an even register (RISC-V ILP32 / Xtensa both require it) and pxx was packing
  it right after the pointer. Tested by inserting a dummy word so the pair lands
  aligned: **still 0 ticks**. Hypothesis dead — do not "fix" this.
- **Not a dead timer subsystem or a stalled qemu.** `esp_timer_is_active`
  returns true after start, and `esp_timer_get_time` advances 3166 ms across the
  wait — ~31 periods that produced no callback.
- **Not the callback crashing on entry.** Adding an `esp_rom_printf` as the
  first statement of the callback prints nothing at all: it is never entered.
- **Not `--no-signals`.** Both variants pass it (without it the program panics
  earlier with `Environment call from M-mode` — a separate known trap).

## Two more hypotheses killed (2026-08-02, same session)

- **It is not about `@OnTick` at all.** Replacing the extra statement with a
  filler that never mentions the callback — `esp_rom_printf('filler=%d', 1)` —
  ALSO makes it fire (29/29). Any ~16 bytes of extra code in `app_main` does. So
  the proc-address fixup is exonerated too: this is pure layout sensitivity.
- **Not the esp_timer task's stack.** Our callback runs on it, and the SDK
  default is only 3584 bytes, so an oversized pxx frame was a good suspect.
  `CONFIG_ESP_TIMER_TASK_STACK_SIZE=16384`: still 0 ticks.
- **Relocations are structurally identical** between the two objects
  (`objdump -r`): same kinds, same counts modulo the extra statement's own
  entries. Worth noting separately: BOTH objects carry three
  `R_RISCV_32 .text-0x00000001` records — the "bodyless routine links as
  entry-1" landmine — but they are present in the WORKING build too, so they are
  not this bug. They may still be a latent one.
- Section placement is ordinary linker output (`.text 0x42008178 0x28958`,
  `.data 0x3fc8a318 0x5d0`, `.bss 0x3fc8ca58 0x251c`) — nothing at a fixed
  address, nothing obviously overlapping.

## What that leaves

The behaviour flips on an unrelated statement, so it is **layout-sensitive**:
image layout, not logic. Something in the image that MOVES when the object's code size changes and that
the SDK depends on — the alarm interrupt's delivery being the visible casualty.
Candidates not yet excluded: a symbol our object defines that the linker prefers
over the SDK's; a cache/IRAM boundary the 16-byte shift crosses; memory written
by our startup that belongs to IDF.

Next measurement: attach a debugger rather than perturb the source further —
`esp_run.sh`'s qemu with the IDF gdbstub, breakpoint on the esp_timer dispatch
path, and see whether the alarm interrupt arrives at all in the failing build.
Perturbation experiments have gone as far as they can: every source-level
hypothesis above died, and the remaining ones (something the image's layout
moves under the SDK) need to be watched, not guessed.

## Note for the reader who assumes this is a regression

Unverified either way. The demo's own log claims `tick=1..5` on esp32c3 when it
landed (2026-07), and ESP-IDF has been upgraded to v6.0.1 since. Whether the
compiler regressed or the SDK moved is an open question — and note that a bisect
would be treacherous here: with the outcome flipping on 16 bytes of unrelated
code, an old commit that "works" may only be lucky.

## Acceptance

- Variant A fires 30/30 without the extra statement, on esp32c3 AND esp32s3.
- `examples/esp32/timer-c3` and `examples/esp32/timer-s3` print
  `tick=1..5 / done ticks=5 status=0` under qemu.
- A regression test that would have caught it: the timer demo's output, checked
  in a make target rather than a README.
