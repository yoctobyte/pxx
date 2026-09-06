---
prio: 40
track: A
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `python3 tools/size_canary.py`. The job's own `src` (`tools/size_canary.py`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory red: size-canary#src:tools/size_canary.py at 2a4cd0bcf664 in step 1/1, `python3 tools/size_canary.py` (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T19:19:45Z
- **Test source:** tools/size_canary.py
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/size_canary.py`.
  ```
  python3 tools/size_canary.py
  ```

## Repro
`tools/testmgr.py --tier native --job 'size-canary#src:tools/size_canary.py'` at 2a4cd0bcf664276c4d8cff4ed35d0ac1cb2de208

## Range
> **The named sha `2a4cd0bcf664` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2a4cd0bcf664`, last good `c1fe3e414d25`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
size-canary: baseline 4039216a7f25 (2026-08-30T00:58:40+02:00)
  subject              code    d(code)         data    d(data)          bss     d(bss)
  esp32c3-bare        57900      +7372        576       +232     103728        +36
  esp32s3-bare        46436      +2984        576       +232     103728        +36
  esp32s2-bare        46436      +2984        576       +232     103728        +36
  esp32-bare          46436      +2984        576       +232     103728        +36
  x86_64-empty        65304      +4025       2792       +832      43524      +1072

size-canary: 1 FAILURE(S)
  esp32c3-bare.code: 50528 -> 57900 (+7372, +14.6%), over the allowed 55580

A size that moved is not automatically a defect — but it is always a decision. Either fix what grew, or re-baseline with tools/size_canary.py --update and say why in the commit.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGE 2026-09-06 (frank-coordinator) — re-laned T -> A, and the reported FAILURE is not the finding

**Re-laned to A.** The fallback header is right that the failing step names no owner. The
lane follows the finding below, which is a property of the riscv32 backend and not of
whatever grew.

### The canary reports one failure and four passes, and the four passes carry the result

Read the five subjects as one experiment rather than five thresholds. The four ESP bare
profiles are **the same program built for four parts**, so their deltas are directly
comparable:

```
subject         d(code)   d(data)   d(bss)     arch
esp32-bare        +2984      +232      +36      xtensa
esp32s2-bare      +2984      +232      +36      xtensa
esp32s3-bare      +2984      +232      +36      xtensa
esp32c3-bare      +7372      +232      +36      riscv32   <- the only reported FAILURE
x86_64-empty      +4025      +832    +1072      x86-64
```

**`d(data)` and `d(bss)` are IDENTICAL across all four ESP subjects, and `d(code)` is
not.** Identical data and bss say one shared addition of one size. The code column says
the same addition costs **+7372 on riscv32 against +2984 on xtensa — 2.5x, a differential
of +4388 bytes.** The three xtensa targets are a control group and they agree with each
other *exactly*, which is what makes the fourth number mean something.

So the growth itself is a decision (the canary's own closing line says so, correctly).
**The differential is a measurement, and it is the part with a defect-shaped answer.**

### Why this must not be closed by `--update`

`tools/size_canary.py --update` is the right remedy for a size that moved deliberately,
and it would clear this red — **and it would freeze the +4388 as the new normal, at which
point the one number in this report that is anomalous becomes invisible forever.** The
canary is a DELTA gate: it can only ever say "this moved", so a re-baseline is also the
only mechanism by which a real regression can be permanently blessed. Take the
differential first, then re-baseline, then say both things in the commit.

### What is NOT established here

- **No cause is named and none should be inferred from this ticket.** Range is
  `c1fe3e414d25..2a4cd0bcf664`, four commits touching buildable files: `75d7d3dcc`
  (`-O3` inline depth budget, `defs.inc` `ir.inc`), `5435c14a7` (C array typedef,
  `cparser.inc` `defs.inc`), `f6ddab6ef` (`builtinheap.pas`, live heap accounting),
  `8727b1907` (`symtab.inc`). **All five subjects grew, x86_64 included**, so it is not
  ESP-specific and it need not be one commit.
- The 2.5x is measured on ONE addition. It is not a claim that riscv32 codegen is 2.5x
  bigger in general — that is the next measurement, not this one.
- The baseline is from `4039216a7f25`, **2026-08-30**, seven days back. Every delta above
  is against a week-old tree, not against the previous run.

### The eliminations, with their assumption named

*"The three xtensa targets agree exactly, so the addition is one size"* is sound only if
the four ESP profiles really do build the same source. They are four entries in one
canary with one bare profile, which is why the comparison is offered at all — but the
person who takes this should confirm it rather than inherit it from me, because the whole
finding rests on that single premise.

### Note this is an ADVISORY row, not a gate

The header says so: nothing day-to-day depends on this path. That is exactly why it has
sat since **2026-09-05T19:19:45Z** with no owner. An advisory red is the one that gets
stepped over, and this one is carrying a real number.
