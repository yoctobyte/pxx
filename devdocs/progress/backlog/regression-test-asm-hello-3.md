---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/hello.pas red at 44ec32358394 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-31T02:13:02Z
- **Test source:** test/hello.pas

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/hello.pas'` at 44ec3235839407258c94d51cc8940936fe7b2863

## Range
> **The named sha `44ec32358394` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `44ec32358394`, last good `c6c3c9d2bb26`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-430046/test_asm_dis_hello26.s  [-S disassembly]
ok: /tmp/testmgr-scratch-430046/test_asm_dis_hello26  [code=65304B  data=2760B  bss=42468B  procs=130]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
