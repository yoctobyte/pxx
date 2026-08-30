---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/hello.pas red at 97c5fba007f9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:28:11Z
- **Test source:** test/hello.pas

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/hello.pas'` at 97c5fba007f96db42b4f4a5698512b66355632df

## Range
> **The named sha `97c5fba007f9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `97c5fba007f9`, last good `31198d3674df`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-619868/test_asm_dis_hello26.s  [-S disassembly]
ok: /tmp/testmgr-scratch-619868/test_asm_dis_hello26  [code=65360B  data=2760B  bss=42452B  procs=129]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
