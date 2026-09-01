---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:tools/compiler_srchash.sh at c1f7471fe1d0 in step 95/57, `if command -v gcc >/dev/null 2>&1; then \ printf '#inclu` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T07:47:04Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +7
- **Failing step:** line 95 of 57 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  if command -v gcc >/dev/null 2>&1; then \ printf '#include <stdio.h>\n#include <string.h>\n#include <dlfcn.h>\nint main(int c,char**v){void*h=dlopen(v[1],RTLD_NOW);if(!h){printf("dlopen: %%s\\n",dlerror());return 1;}int(*a)(int)=dlsym(h,"shared_c_addup");const char*(*t)(void)=dlsym(h,"shared_c_tag")
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:tools/compiler_srchash.sh'` at c1f7471fe1d0938a68f491a6cfe3dd73535c757a

## Range
> **The named sha `c1f7471fe1d0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c1f7471fe1d0`, last good `6bd4d64fff57`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
self-host fixedpoint: verified — 1 round(s), 1ac459a3e2ac (stamp read back; sources match it)
emit-obj-target-set: ok -- dispatch, refusal and --help all name i386,riscv32,x86-64,xtensa (refused: aarch64 arm32 wasm32); cli.md names them all
ok: /tmp/testmgr-scratch-1228868/test_emit_obj_x64.o  [code=108811B  data=5192B  bss=42344B  procs=254]
/usr/bin/ld: warning: /tmp/testmgr-scratch-1228868/test_emit_obj_x64.o: missing .note.GNU-stack section implies executable stack
/usr/bin/ld: NOTE: This behaviour is deprecated and will be removed in a future version of the linker
test-emit-obj: x86-64 .o links+runs under a gcc-built main ok
/usr/bin/ld: warning: /tmp/testmgr-scratch-1228868/test_emit_obj_x64.o: missing .note.GNU-stack section implies executable stack
/usr/bin/ld: NOTE: This behaviour is deprecated and will be removed in a future version of the linker
test-emit-obj: x86-64 .o links+runs as a PIE too
clang not installed; second-linker PIE check skipped
ok: /tmp/testmgr-scratch-1228868/test_shared_libc26.so  [code=99403B  data=1480B  bss=38164B  procs=402]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_shared_libc26_dlopen]
--- expected
+++ actual
@@ -1 +1 @@
-pxx-c-shared
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-emit-obj#src:tools/compiler_srchash.sh` passes at fc2adb7ec261 (tier full); it was red at c1f7471fe1d0. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
