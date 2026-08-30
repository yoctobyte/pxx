---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-lua-cross#src:compiler/.pascal26.fixedpoint red at b695bcb4b192 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T14:03:47Z
- **Test source:** compiler/.pascal26.fixedpoint test/lua/runner.c +1

## Repro
`tools/testmgr.py --tier full --job 'test-lua-cross#src:compiler/.pascal26.fixedpoint'` at b695bcb4b19264847cedc6c01678d4e298d14cfb

## Range
> **The named sha `b695bcb4b192` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b695bcb4b192`, last good `4d3f8a4eac00`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1439: error: target aarch64: external call with more than 8 parameters not supported
(tail)
sed as value (treated as 0)
pascal26:384: warning: undeclared identifier 'LC_TIME' used as value (treated as 0)
ok: /tmp/testmgr-scratch-3570220/pxx_lua_arm32  [code=2371436B  data=42352B  bss=70148B  procs=1874]
test-lua-cross: PASS arm32 closures.lua
test-lua-cross: PASS arm32 coroutines.lua
test-lua-cross: PASS arm32 files.lua
test-lua-cross: PASS arm32 numeric.lua
test-lua-cross: PASS arm32 oop.lua
test-lua-cross: PASS arm32 strings.lua
test-lua-cross: building lua for i386 ...
pascal26:4: warning: "/*" within comment
pascal26:383: warning: undeclared identifier 'LC_COLLATE' used as value (treated as 0)
pascal26:383: warning: undeclared identifier 'LC_CTYPE' used as value (treated as 0)
pascal26:383: warning: undeclared identifier 'LC_MONETARY' used as value (treated as 0)
pascal26:384: warning: undeclared identifier 'LC_TIME' used as value (treated as 0)
ok: /tmp/testmgr-scratch-3570220/pxx_lua_i386  [code=1138540B  data=42304B  bss=70148B  procs=1840]
test-lua-cross: PASS i386 closures.lua
test-lua-cross: PASS i386 coroutines.lua
test-lua-cross: PASS i386 files.lua
test-lua-cross: PASS i386 numeric.lua
test-lua-cross: PASS i386 oop.lua
test-lua-cross: PASS i386 strings.lua
test-lua-cross: building lua for riscv32 ...
pascal26:4: warning: "/*" within comment
pascal26:383: warning: undeclared identifier 'LC_COLLATE' used as value (treated as 0)
pascal26:383: warning: undeclared identifier 'LC_CTYPE' used as value (treated as 0)
pascal26:383: warning: undeclared identifier 'LC_MONETARY' used as value (treated as 0)
pascal26:384: warning: undeclared identifier 'LC_TIME' used as value (treated as 0)
ok: /tmp/testmgr-scratch-3570220/pxx_lua_riscv32  [code=2436972B  data=42352B  bss=70148B  procs=1874]
test-lua-cross: PASS riscv32 closures.lua
test-lua-cross: PASS riscv32 coroutines.lua
test-lua-cross: PASS riscv32 files.lua
test-lua-cross: PASS riscv32 numeric.lua
test-lua-cross: PASS riscv32 oop.lua
test-lua-cross: PASS riscv32 strings.lua
test-lua-cross: FAILURES

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
