---
track: A
prio: 60
type: bug
blocked-by: []
summary: "pxx cannot compile its own source at -O0: `error: code overflow` at compiler.pas:170295. The default level builds fine, so `make compiler/pascal26` and the self-host fixedpoint both pass — the per-fix gate is structurally blind to it. Surfaced by the bench's selfcompile row dropping 4 variants to 1."
status: done
owner: frankonpiler-an
---

# Self-compile at `-O0` overflows the code buffer

- **Type:** bug (codegen / buffer sizing) — **Track A**
- **Opened:** 2026-08-19
- **Filed by:** Track T from the bench series. T owns the tool, never the bug.

## Reproduce

```sh
make compiler/pascal26            # OK — default level
./compiler/pascal26 -O0 compiler/compiler.pas /tmp/p26_O0
  pascal26:170295: error: code overflow
    near:  ProcCount  ]   >>> end  unit
```

## Why every gate missed it

`make compiler/pascal26` builds at the **default** optimisation level, and the
self-host fixedpoint proves byte-identity at that level. Neither runs `-O0` over
`compiler.pas`. So a `-O0`-only failure passes:

- the per-fix gate (`make compiler/pascal26` + repro + `gate.sh quick`),
- the self-host fixedpoint,
- `--tier native` and `--tier full`, whose selfhost job is the same default-level chain.

The coordinator's counter-evidence — *"every commit in that range landed through
`make compiler/pascal26`, which IS the byte-identical self-host fixedpoint"* — is
true and does not cover this, because the gate and the failure are at different
`-O` levels. Worth stating plainly: **passing the self-host gate is not evidence
that the compiler compiles itself**, only that it does so at one optimisation
level.

## How it surfaced, and what the bench row actually said

`tstate/bench.tsv` selfcompile dropped from 4 rows to 1 between `18bcb92ffb8b`
(ok, 30 rows) and `9cc61eee29c8` (RED, 27). Every other benchmark — fib,
mandelbrot(-p), nbody, raytracer(-p), sieve — was identical across both runs, so
the whole delta was selfcompile. The watcher log names the cause:

```
bench selfcompile  -O0  COMPILE-FAIL
bench selfcompile  -O2  CANARY-DIFF vs -O0
bench selfcompile  -O3  CANARY-DIFF vs -O0
bench selfcompile  fpc    6780.8ms
```

**This is ONE defect, not three.** `-O2`/`-O3` report `CANARY-DIFF vs -O0`
because the canary compares against the `-O0` build, which did not exist. The
`fpc` row survives because it uses FPC, not pxx. So the row-count drop is a
single `-O0` compile failure cascading through two dependent checks.

A row-count drop is a **failure to produce a measurement**, not a slow one —
which is what distinguished this from the repo's two previous bench reds
(co-tenancy, p-state quantisation), both timing artefacts. Worth keeping as the
discriminator: missing rows point at the subject, slow rows at the box.

## Not the harness

Checked before filing, since "the bench harness broke" was the competing
hypothesis and the cheaper conclusion. It reproduces by hand outside the
harness, at HEAD, on a quiet box, in one command. The bench is reporting
correctly.

## Suggested first look

`code overflow` at `compiler.pas:170295` reads as an emitted-code buffer sized
for the default level's output being exceeded by `-O0`'s larger, unoptimised
code. If so the fix is a bound, not a codegen bug — but that is Track A's call,
and the line number is where to start.

## Gate

`./compiler/pascal26 -O0 compiler/compiler.pas` succeeds, plus the usual
self-host fixedpoint. Worth considering whether the gate should compile itself
at `-O0` as well, since this class is invisible otherwise — that would be a
Track T tier change, filed separately if Track A wants it.


---

## RESOLVED 2026-08-19 — it was a bound, and the margin was gone at every level

Measured at HEAD with a probe build (MAX_CODE temporarily 32 MB) so the real
requirement could be read rather than guessed:

| level | code bytes | vs the old 8388608 cap |
| --- | --- | --- |
| `-O0` | 8394698 | **over by 6090 B (0.07%)** |
| `-O1` | 7458182 | 89% |
| `-O2` (= default) | 7415348 | 88% |
| `-O3` | 7561519 | 90% |

So the ticket's "suggested first look" was right — no codegen defect, the
emitted-code buffer was simply too small. But the framing "an `-O0` problem"
understates it: **every** level sat at 88-90% of the cap. `-O0` was not special,
it was merely first across a line all four were standing on. A few hundred KB of
ordinary compiler growth would have taken the default build down too, and that
failure would have been indistinguishable from a real bug.

**Fix:** `MAX_CODE` 8 MB -> 16 MB (`compiler/defs.inc`), taking the default
build from 88% to 44%. The cost is virtual BSS only — `Code[]` plus
`AsmDisProcAtPos` at 4 B per code byte, and the latter is touched only by `-S`.
Reported BSS goes 166 MB -> 209 MB; resident does not, since untouched BSS pages
are never faulted in.

**Also:** `Error('code overflow')` now names the cap, points at `defs.inc`, and
states the inversion that made this confusing — *lower* `-O` levels emit *more*
code, so a build that fits at `-O2` can still overflow at `-O0`. The bare old
message cost Track T a bench investigation because it could not distinguish
"just over the line" from "runaway emission", and those want opposite fixes. It
lives in `ErrorCodeOverflow` rather than inline in `EmitB` so the hot path stays
a compare and a store. (No `IntToStr` in the text: `emit.inc` is included long
before any int-to-string helper is in scope, and the constant's value was never
the missing information.)

## Verified

```
-O0  ok  code=8394891   -O1  ok  code=7458375
-O2  ok  code=7415541   -O3  ok  code=7561720
```

and the stronger property the bench's canary was reaching for — a compiler built
at **any** of the four levels emits a **byte-identical** compiler:

```
q-O0 q-O1 q-O2 q-O3  ->  all fdf98a61a72d89cb
```

Plus `make compiler/pascal26` converged after 1 round (self-host fixedpoint) and
`tools/gate.sh quick`.

## What this does NOT fix

The gate is still blind to this class: nothing in the per-fix loop or any Track T
tier compiles `compiler.pas` at `-O0`, so the next `-O0`-only regression will
again be found by a benchmark or not at all. Raising the cap bought headroom, not
coverage. That question is
[[decide-should-the-gate-prove-self-compile-at-more-than-one-o-level]] — the
human's call, and Track T's to implement either way. I have deliberately not
acted on it.

## Log
- 2026-08-19 — resolved, commit 6b2402b92.
