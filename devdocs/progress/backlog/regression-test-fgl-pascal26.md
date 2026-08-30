---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-fgl#src:compiler/.pascal26.fixedpoint red at 719bef10ea68 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T16:10:37Z
- **Test source:** compiler/.pascal26.fixedpoint tools/run_fgl_corpus.sh

## Repro
`tools/testmgr.py --tier full --job 'test-fgl#src:compiler/.pascal26.fixedpoint'` at 719bef10ea68c09b3b5fac29989e24026e93c7fa

## Range
> **The named sha `719bef10ea68` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `719bef10ea68`, last good `a8947307fa98`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL objectlist.pas -- compile error:
pascal26:9: error: generic constraint violated: TFPGObjectList<T> is constrained to `TObject`, but TThing is not TObject or a descendant of it
(tail)
self-host fixedpoint: verified — 1 round(s), 1f92bfac64f4
PASS fpslist.pas
PASS ifclist.pas
PASS list_int.pas
PASS list_str.pas
PASS map_int.pas
PASS map_str.pas
FAIL objectlist.pas -- compile error:
    pascal26:9: error: generic constraint violated: TFPGObjectList<T> is constrained to `TObject`, but TThing is not TObject or a descendant of it
      near: = specialize TFPGObjectList < TThing > >>> ; constructor TThing 
test-fgl: 6 pass, 1 fail, 0 skip (of 7)
test-fgl: FAILURES: objectlist.pas(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
