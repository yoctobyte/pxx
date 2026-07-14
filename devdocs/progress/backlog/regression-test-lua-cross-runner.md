---
prio: 70
---

# regression: test-lua-cross#src:test/lua/runner.c red at 940b261f8678 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-14T15:02:20Z
- **Test source:** test/lua/runner.c tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-lua-cross#src:test/lua/runner.c'` at 940b261f8678c2d8faa70035fe60e91f9f0c7a3f

## Range
bad `940b261f8678`, last good `940b261f8678`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test/lua/coroutines.expected	2026-07-07 21:09:56.569456018 +0200
+++ /tmp/testmgr-scratch-1502541/pxx_lua_got.txt	2026-07-14 16:59:56.644203901 +0200
@@ -1,2 +0,0 @@
-sum-of-squares	55
-resume	11	200
test-lua-cross: FAIL i386 files.lua
--- test/lua/files.expected	2026-07-07 21:09:56.569456018 +0200
+++ /tmp/testmgr-scratch-1502541/pxx_lua_got.txt	2026-07-14 16:59:56.921402990 +0200
@@ -1,3 +0,0 @@
-alpha
-BETA
-
test-lua-cross: FAIL i386 numeric.lua
--- test/lua/numeric.expected	2026-07-07 21:09:56.569456018 +0200
+++ /tmp/testmgr-scratch-1502541/pxx_lua_got.txt	2026-07-14 16:59:57.176105934 +0200
@@ -1,8 +0,0 @@
-3.14
-4.0
-1024.0
-3.5
-3.14
-4.0
-3.1416
-mean=5.00 sd=2.00
test-lua-cross: FAIL i386 oop.lua
--- test/lua/oop.expected	2026-07-07 21:09:56.569456018 +0200
+++ /tmp/testmgr-scratch-1502541/pxx_lua_got.txt	2026-07-14 16:59:57.411395934 +0200
@@ -1,3 +0,0 @@
-cat makes a sound
-rex barks
-rex
test-lua-cross: FAIL i386 strings.lua
--- test/lua/strings.expected	2026-07-07 21:09:56.569456018 +0200
+++ /tmp/testmgr-scratch-1502541/pxx_lua_got.txt	2026-07-14 16:59:57.711391614 +0200
@@ -1,4 +0,0 @@
-HELLO, WORLD	12	Hello
-Hell0, W0rld
-brown,fox,quick,the
-9 8 5 3 2 1
test-lua-cross: building lua for riscv32 ...
pascal26:4: warning: "/*" within comment
pascal26:27216: warning: undeclared identifier 'LC_COLLATE' used as value (treated as 0)
pascal26:27216: warning: undeclared identifier 'LC_CTYPE' used as value (treated as 0)
pascal26:27216: warning: undeclared identifier 'LC_MONETARY' used as value (treated as 0)
pascal26:27217: warning: undeclared identifier 'LC_TIME' used as value (treated as 0)
ok: /tmp/testmgr-scratch-1502541/pxx_lua_riscv32  [code=2033192B  data=16864B  bss=8136B  procs=1672]
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
