---
slug: bug-wasm-compiling-compiler-pas-for-wasm32-needs-tens-of-gb
title: "wasm32 accumulated the .wat text with O(n^2) string appends — any large procedure body, not just compiler.pas"
track: A
type: bug
prio: 60
status: done
found: 2026-08-28
found-by: frankwasm (measured; it starved a 60 GB box and killed sibling jobs)
---

## The fact

```
pascal26 --target=wasm32 -Fulib/rtl/platform/wasi compiler/compiler.pas out.wasm
```

- Observed at **52.1 GB RSS and still climbing** after 26 minutes at 100% CPU, on a
  60 GB box with 58 GB used and 1 GB available. It was killed to free the machine.
- Under `ulimit -v 8000000` it dies of **SIGSEGV** at peak 7.6 GB after ~130 s — an
  allocation failure surfacing as a crash, not as a diagnostic.
- It does terminate given enough memory: an earlier run completed and reported
  `3222 of 3650 bodies lowered`. So the appetite is finite and extreme, not
  strictly unbounded.

The native compile of the same file is ordinary — `make compiler/pascal26` finishes
in seconds. This is specific to `--target=wasm32` on this input.

## Four controls, so the cause is not guessed

| control | result | rules out |
| --- | --- | --- |
| pre-`in` backend vs current, same input, same cap | **7600540 KB / 144 s** vs **7600416 KB / 128 s** — identical | the `in` lowering that landed the same hour (`f3116b244`) |
| 1600 `in` expressions, synthetic | **300 MB, flat** from 100 → 1600 | `in` density generally |
| the same program with `in` rewritten as explicit comparisons | **1378 MB** — *higher* than `in` | `in` being expensive at all |
| 200 / 800 / 3200 procedure bodies, synthetic | **302 / 304 / 326 MB** | body count |

Binaries named: `a874b8800dc2` (pre-`in` + probe), `c185218f2608` (with `in` + probe),
both self-host-converged. The probe is the `EmitZeroFrameSlot` wasm no-op described
in `devdocs/dev/wasm/PLAN.md` — needed only so the compile gets past
`bug-a-emitzeroframeslot-has-no-wasm32-arm`, and it is not the cause either, since
both arms of the A/B carry it.

So it is neither `in`, nor set density, nor body count. It is something about
`compiler.pas` specifically — the largest and most varied input the wasm32 backend
has ever been given — and the four controls above are what a fix should keep green.

## Why it matters beyond the number

**It blocks Phase 9's anchor.** The phase's goal is `pascal26` itself running under a
WASI host; that requires compiling `compiler.pas` to wasm32, which is exactly this
command. Coverage measurement for the phase currently runs only when the box happens
to have ~55 GB free, which is not a workable instrument.

**It has a blast radius.** At 58 of 60 GB the machine had no headroom and background
jobs on this box were killed — including this lane's own, which read as arbitrary
harness behaviour for several turns before the memory was measured. Anyone re-running
this command should cap it (`ulimit -v`) rather than trust it to be polite.

## Two things a fix should address

1. **The consumption itself.** Untriaged — the obvious suspects are the encoder
   holding every function body before emitting, and any O(n²) over relocations or
   patch sites, but neither has been measured and this ticket deliberately does not
   claim one.
2. **The failure mode.** Exhaustion produces SIGSEGV. An out-of-memory condition
   should say so; a segfault sends whoever hits it looking for a pointer bug that
   is not there. This half is cheap and independent of the first.

## Repro (cap it)

```
( ulimit -v 8000000; timeout 400 ./compiler/pascal26 --target=wasm32 \
    -Fulib/rtl/platform/wasi compiler/compiler.pas /tmp/o.wasm )   # SIGSEGV ~130s
```

Needs the `EmitZeroFrameSlot` probe to reach this point at all; without it the
compile stops earlier at that known blocker.

## RESOLVED 2026-08-28 — root cause found, fixed on branch `wasm` (d8c1a3635)

`compiler/wasmenc.inc`, `WasmText`:

```pascal
WFText := WFText + WasmIndentStr + t + LineEnding;   { once per instruction }
```

Repeated AnsiString append: each call allocates a fresh string of the whole
accumulated length and copies it, so a body of n instructions costs sum(i)
bytes. `WFText` resets per function, so the peak is set by the **largest single
body**. Replaced with the grow-by-doubling pool `WasmDataSeg` already uses in
that file, materialising the AnsiString once per body.

| 300 if/else in ONE procedure | peak | wall |
| --- | --- | --- |
| before | 7179 MB | 107.6 s |
| after | **31 MB** | **0.51 s** |
| x86-64, same input | 29 MB | 0.40 s |

`compiler.pas` for wasm32 now completes in **595 MB / 26.5 s** where it
previously reached 52 GB without finishing. Output preservation verified in the
strong form: all 16 `*_slice.pas` compiled to .wat by the pre-fix binary
(`2e68d018ccac`) and the fixed one (`966177c0b3f2`) are byte-identical.

**Nothing to apply on master.** `compiler/wasmenc.inc` does not exist here — it
is branch-local — so master was never affected. The fix arrives with the branch
merge. The ticket lives here because this lane publishes findings to master for
visibility, not because the defect was ever on master.

### Two corrections to what this ticket originally said

**The title and scope understated it.** It was filed as a `compiler.pas`
problem blocking Phase 9's anchor. The real scope is *any* wasm32 compile of a
program with a large procedure body — 300 statements is enough to reach 7 GB,
which is not exotic. prio raised 50 → 60 on that basis: the ranking's stated
premise was superseded by its own author's later measurement.

**Both mechanisms this ticket floated were wrong** — "the encoder holding every
function body" and "an O(n²) over relocations or patch sites". The ticket
deliberately declined to name either as the cause, which is the only reason
nothing had to be retracted. The four controls it was filed with all survived.

### The measurement note worth keeping

Three synthetics measured flat before one caught it: 3200 procedures (326 MB),
1600 `in` expressions (300 MB), a library-heavy program (315 MB). All three
varied body COUNT and held body SIZE near zero. **A control that reports "no
effect" is worth exactly what its axis is worth.** What localised the bug was
not any of them but native-flat-on-identical-input — 30 MB on x86-64 and i386
where wasm32 took 827/3213/7180 — which put the cause in the wasm32 path before
any code was read.

The secondary defect stands and is NOT fixed: exhaustion still surfaces as
SIGSEGV rather than an out-of-memory diagnostic. Split out as its own concern
for whoever wants it; it is independent of this fix and much cheaper now that
the pathological case is gone.
