---
slug: bug-wasm-compiling-compiler-pas-for-wasm32-needs-tens-of-gb
title: "Compiling compiler.pas for wasm32 consumes tens of GB and segfaults under a cap — it blocks Phase 9's anchor"
track: A
type: bug
prio: 50
status: backlog
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
