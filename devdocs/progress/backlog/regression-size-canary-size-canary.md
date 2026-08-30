---
prio: 40
track: T
---

> **Track T by default: no lane could be inferred** from `tools/size_canary.py`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: size-canary#src:tools/size_canary.py red at 83fb0ef72419 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T13:24:51Z
- **Test source:** tools/size_canary.py

## Repro
`tools/testmgr.py --tier native --job 'size-canary#src:tools/size_canary.py'` at 83fb0ef72419b46cf22dd1ce57885950574d69ef

## Range
> **The named sha `83fb0ef72419` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `83fb0ef72419`, last good `42fde2a7e025`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
size-canary: baseline 4039216a7f25 (2026-08-30T00:58:40+02:00)
  subject              code    d(code)         data    d(data)          bss     d(bss)
  esp32c3-bare        66252     +15724        496       +152     103692          0
  esp32s3-bare        56684     +13232        496       +152     103692          0
  esp32s2-bare        56684     +13232        496       +152     103692          0
  esp32-bare          56684     +13232        496       +152     103692          0
  x86_64-empty        69400      +8121       2712       +752      42452          0

size-canary: 5 FAILURE(S)
  esp32c3-bare.code: 50528 -> 66252 (+15724, +31.1%), over the allowed 55580
  esp32s3-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  esp32s2-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  esp32-bare.code: 43452 -> 56684 (+13232, +30.5%), over the allowed 47797
  x86_64-empty.code: 61279 -> 69400 (+8121, +13.3%), over the allowed 67406

A size that moved is not automatically a defect — but it is always a decision. Either fix what grew, or re-baseline with tools/size_canary.py --update and say why in the commit.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
