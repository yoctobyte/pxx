---
slug: bug-t-code-is-page-quantised-so-there-is-no-instrument-for-size-work
title: "`code=` in the `ok:` line is page-quantised, so no size work below 4 KiB is measurable"
track: T
prio: 60
type: bug
status: new
created: 2026-09-18
owner: ""
summary: "The compiler's `ok: [code=NB ...]` line reports the CODE SEGMENT's page-rounded extent, not the bytes emitted. Measured 2026-09-18 on x86-64: `0xe8 + 3864 = 0x1000`, `0xe8 + 69400 = 0x11000`, `0xe8 + 20248 = 0x5000` — every row is the page ceiling. Real code, trailing zeros stripped, is 600 B and 195 B for the two rows both reported as 3864. The consequence is that `--no-signals`, which removes exactly 405 bytes in every configuration, reads as a NO-OP in all seven measured configurations, and a seat concluded the flag was broken and went looking in the parser and the dispatcher. Both umbrella-a-hosted-program-is-as-small-as-it-can-be and umbrella-an-esp32-image-is-as-small-as-it-can-be need a byte-accurate figure before any of their work can be graded. symtab.inc:14858 and pyparser.inc:46611 both already record the quantisation in comments; nothing surfaces it at the point of use."
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
