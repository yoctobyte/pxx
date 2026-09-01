---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 2 of 2, `if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ echo "test-lua-cross: SKIP — no lua tree at library_candidates/lu`, which names `test/lua/runner.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-lua-cross#src:tools/compiler_srchash.sh at e5a21152b5d1 in step 2/2, `if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ e` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T05:58:19Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +2
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/lua/runner.c tools/run_target.sh`.
  ```
  if [ ! -f "library_candidates/lua/src/lua.h" ]; then \ echo "test-lua-cross: SKIP — no lua tree at library_candidates/lua/src"; exit 0; \ fi; \ overall=0; \ for T in aarch64 arm32 i386 riscv32; do \ if ! command -v qemu-$T >/dev/null 2>&1 && ! command -v qemu-${T%32} >/dev/null 2>&1; then \ echo "te
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-lua-cross#src:tools/compiler_srchash.sh'` at e5a21152b5d1d0d763b5b676110e4558978946e0

## Range
bad `e5a21152b5d1`, last good `a3b1af61a27f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
' used as value (treated as 0)
pascal26:384: warning: undeclared identifier 'LC_TIME' used as value (treated as 0)
ok: /tmp/testmgr-scratch-307439/pxx_lua_arm32  [code=2404204B  data=42640B  bss=74556B  procs=1931]
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
ok: /tmp/testmgr-scratch-307439/pxx_lua_i386  [code=1421164B  data=42592B  bss=74556B  procs=1897]
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
ok: /tmp/testmgr-scratch-307439/pxx_lua_riscv32  [code=2514796B  data=42640B  bss=74556B  procs=1931]
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
