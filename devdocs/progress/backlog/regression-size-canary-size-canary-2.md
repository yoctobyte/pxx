---
prio: 40
track: T
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
