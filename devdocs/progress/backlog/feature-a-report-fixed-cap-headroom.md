---
track: A
prio: 40
type: feature
blocked-by: []
summary: "Three fixed caps in defs.inc have now been raised AFTER a user hit them — MAX_CODE 8->16 MB, MAX_STRS 8192->65536, MAX_CODE 16->32 MB — and each was found by a program failing, never by anyone looking. Nothing reports how close a compile came to any cap, so the only headroom signal the project has is an overflow. Proposal: a PXXDBG=a.caps topic printing per-cap utilisation at end of compile, so `the next one` is a number someone can read instead of an incident. Small, additive, no behaviour change."
status: new
owner: ""
---

# Nothing reports how close a compile came to a fixed cap

- **Type:** feature (compiler diagnostics) — **Track A** (`compiler/**`).
- **Filed:** 2026-08-29 by frankA, from the closing question of
  [[bug-a-cross-bootstrap-aarch64-overflows-max-code]]: *"Does any remaining
  fixed cap there have a headroom check, or do we wait for the third?"*
  **The third had already happened.** That ticket WAS the third.

## The pattern, with dates

| cap | raised | how it was found |
| --- | --- | --- |
| `MAX_CODE` 8 MB -> 16 MB | | a self-compile that failed at `-O0` ONLY, which no gate runs |
| `MAX_STRS` 8192 -> 65536 | | a csmith `--paranoid` program, 15% over, refused mid-compile |
| `MAX_CODE` 16 MB -> 32 MB | 2026-08-29 | `cross-bootstrap` for aarch64, red at HEAD for an unknown period |

Three for three, **every one discovered by a program failing.** Not one by
anybody looking, because there is nothing to look at: no cap's utilisation is
reported anywhere, at any verbosity. `grep` finds no headroom instrumentation in
`compiler/**` — the only per-cap number in the tree is an ad-hoc
`INLINE-MEASURE:` writeln in `ir_codegen.inc`.

The compile summary line reports `code= data= bss= procs=` — **raw counts with
no denominator.** `procs=3401` is 21% of `MAX_PROCS`, and nothing says so.

## Why the third one is the argument

The aarch64 overflow is the clearest case that this is a blind spot rather than
bad luck, because **the cap never moved and the compiler did not suddenly
bloat.** The target list grew underneath a cap that had been sized against
x86-64 alone. aarch64 was at 121.9% and arm32 at 128.6% of the old cap while
x86-64 sat at 55.5% — so the project's mental model of "we are at half the cap"
was true, and true only of the target nobody was worried about.

**A denominator would have shown that the day the ARM targets landed.** No
overflow required, no CI cadence change required — just a number next to a
number.

## Proposal

`PXXDBG=a.caps`: one line per interesting cap at end of compile — name, used,
cap, percent — sorted by percent so the top line is the next one to bite.
Interesting = the ones a real program can move: `MAX_CODE`, `MAX_STRS`,
`MAX_SYMS`, `MAX_PROCS`, `MAX_DATA`, `MAX_FIXUPS`, `MAX_GLOBFIX`,
`MAX_USES_EDGES`, `MAX_CPREP_MACROS`, `MAX_CPREP_CHARS`.

Additive, no behaviour change, off unless asked. The natural consumer is Track
T: a periodic run over the corpus with `a.caps` turns "which cap is next" into a
report rather than an incident.

**Deliberately NOT proposed: making the caps dynamic.** Several already are —
`Code[]` and `AsmDisProcAtPos` are `array of` and grow on demand, so `MAX_CODE`
is a ceiling costing nothing until used. Growing the rest is a separate and much
larger question ([[feature-dynamic-compiler-tables]]); this ticket only asks to
be able to SEE the ceilings, which is cheap and is a prerequisite for arguing
about them either way.

## Gate

Track A's: `make compiler/pascal26` (byte-identical self-host fixedpoint) plus
`PXXDBG=a.caps` on a self-compile showing plausible percentages. Nothing else
can change — the topic is inert unless requested.
