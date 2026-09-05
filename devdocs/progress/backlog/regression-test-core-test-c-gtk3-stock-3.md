---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 3, `./compiler/pascal26 -Futest/gtk3stock -I/usr/include/gtk-3.0/ test/test_c_gtk3_stock.pas /tmp/test_c_gtk3_stock26`, which names `test/test_c_gtk3_stock.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk3_stock.pas at 7867c5481c01 in step 1/3, `./compiler/pascal26 -Futest/gtk3stock -I/usr/include/gtk-3.0/ test/test_c_gtk3_stock.pas /tmp/test_c_gtk3_stock26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-05T17:58:16Z
- **Test source:** test/test_c_gtk3_stock.pas test/gtk3stock/gtk3_c.h +1
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_c_gtk3_stock.pas`.
  ```
  ./compiler/pascal26 -Futest/gtk3stock -I/usr/include/gtk-3.0/ test/test_c_gtk3_stock.pas /tmp/test_c_gtk3_stock26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk3_stock.pas'` at 7867c5481c0126cd79daa92c74114b8dd3fc6ef3

## Range
> **The named sha `7867c5481c01` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7867c5481c01`, last good `b8e3b3010249`, 87 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: C include file not found: "gtk/gtk.h" (searched: /usr/include/gtk-3.0/, /tmp/testmgr-scratch-172642/compiler/../lib/crtl/include/, /tmp/testmgr-scratch-172642/compiler/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
(tail)
pascal26:7: error: C include file not found: "gtk/gtk.h" (searched: /usr/include/gtk-3.0/, /tmp/testmgr-scratch-172642/compiler/../lib/crtl/include/, /tmp/testmgr-scratch-172642/compiler/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
  near: program test_c_gtk3_stock ; uses gtk3_c >>> ; function AutoQuit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
