---
slug: bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work
title: "`code=` in the `ok:` line is page-quantised, so no size work below 4 KiB is measurable"
track: T
prio: 60
type: bug
status: done
created: 2026-09-18
owner: "frankH"
summary: "FIXED 2026-09-18 (frankH). `code=` on the `ok:` line is now EMITTED bytes (the writer's CodePadStart), and the page-padded extent is a new trailing field `codeseg=`. Before the fix it was CodeLen after the ELF writer's filler -- the page ceiling on every hosted target -- so `--no-signals` (405 B) read as a no-op everywhere. Verified: hello on x86-64 reports 67104/66699/18790/18385/600/195 across the six flag rows, matching the independently measured real sizes exactly. Guarded by row (4) of tools/ok_line_means_a_file.sh (gate.sh quick), which fails on the unfixed compiler. The esp-bare-*-data-align8 Makefile rows read `codeseg=` because they need the padded length. size_baseline.json re-baselined; the x86_64-empty drop 69400->67036 is a unit change, not a shrink. Readers of the PINNED compiler still see the old meaning until the next pin."
---

# What

`ok: [code=NB data=NB bss=NB procs=N]` is the only size readout the compiler
offers, and `code=` is the page-rounded segment extent.

Measured 2026-09-18, `WriteLn('hello')`, x86-64, every row verified to run:

| flags | `code=` | real |
| --- | --- | --- |
| `<none>` | 69,400 | 67,104 |
| `--no-signals` | 69,400 | 66,699 |
| `--dce` | 20,248 | 18,790 |
| `--dce --no-signals` | 20,248 | 18,385 |
| `-uPXX_MANAGED_STRING` | 3,864 | 600 |
| `-uPXX_MANAGED_STRING --no-signals` | 3,864 | **195** |

## Why it is a bug and not a rounding nit

**It is an instrument that answers correctly about something else.** It does not
error, it does not warn, and it is the number every ticket in this area quotes.
`--no-signals` removes 405 bytes in all six rows and is invisible in all six,
because 405 bytes cannot cross a 4 KiB boundary. A seat measured all seven
configurations, found byte-identical sizes, verified the flag was parsed
(`compiler.pas:1507`) and the guard present (`ir_codegen.inc:1446`), and
reported an anomaly. There was none.

## Fix

`code=` should report emitted bytes. If the padded extent is also wanted, print
both — `code=195B (segment 3864B)`. Do not change the spelling silently: several
tickets and at least one devtest quote these numbers.

## Positive control

A build whose real code differs from a sibling by less than a page must report
different `code=`. The `--no-signals` pair above is that control and it is free:
195 vs 600 at the floor.

## Resolution (frankH, 2026-09-18)

**Why it was padded** (the ticket asked): it never was on purpose. The ELF
writer appends zero filler to `Code[]` so data starts on its own page
(`PadCodeToPageBoundary`, the 1600x qemu translation-cache fix) and to 8 bytes
(`AlignCodeForData`, the xtensa l32i alignment fix). The `ok:` line printed
`CodeLen` AFTER that append. The writer already recorded where filler begins,
`CodePadStart`, for `-S` — the `ok:` line simply did not read it.

**New line:** `ok: out  [code=67104B  data=4328B  bss=46596B  procs=147  codeseg=69400B]`.
`codeseg=` is appended rather than placed beside `code=` because
`tools/size_canary.py`'s regex needs `code=NB  data=` adjacent.

**Consumers checked** (`grep` over tools/, test/, Makefile for `code=` parsers):
`size_canary.py` (re-baselined, unit change); the two `esp-bare-*-data-align8`
Makefile rows — **these needed the padded length and would have gone red**:
the program's emitted code is 4 mod 8 on both chips (xtensa 103072 / seg
103076, riscv32 126520 / seg 126524); they read `codeseg=` now. Devtest
fixtures that embed a literal `ok:` line do not parse the number.

**Control, both directions:** unfixed compiler, both `--no-signals` rows print
`code=69400B` and row (4) FAILS; fixed, 67104 vs 66699 and it passes.
`gate.sh quick` GREEN with the row live.

**Inert-until-pin:** anything reading the ok line of `$(PXX_STABLE)` sees the
old meaning (and no `codeseg=`) until the next pin. Every in-tree consumer runs
`compiler/pascal26`.

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
