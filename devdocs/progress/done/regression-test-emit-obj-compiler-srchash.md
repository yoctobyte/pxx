---
prio: 70
track: A
status: done
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
---

## Resolution (Track A, frankA)

**Already fixed. This is a red I disclosed deliberately, sampled in the window
between the disclosure and the fix.** Verified green at HEAD `0596c9d0d`:
`test-emit-obj` exits 0 with zero `expect_same: MISMATCH` lines.

**Independently corroborated, and by a source I did not pick:** the seven
watcher auto-closed this ticket on its own (the Log line above) after seeing the
job pass at `fc2adb7ec` — a different host, a different commit, and a full tier
rather than my single target. Two greens that could have disagreed and did not.

**THE BISECT WILL NAME THE WRONG COMMIT, AND IT IS WORTH SAYING SO.** The
watcher's range holds two buildable commits, `7d1aed2b5` (mine) and `19125e02e`
(an xtensa size fix that cannot reach an x86-64 C dlopen row), so an idle bisect
lands on `7d1aed2b5` and calls it bad. That commit changed four Makefile `;`
chains to `&&`. It introduced no defect — it removed the thing that had been
**swallowing** one. The `@if` block's status had been whichever command ran
last, and the last command was an `echo`, so a failing `expect_same.sh` exited 1
into a block that then reported success.

The actual defect dates to `46586dba8`, the commit that added
`test/test_shared_lib.c`: the C frontend emits `CompilePendingGlobalInits` at
the start of `main`, and a library is precisely a translation unit with **no**
`main`, so a `.so` emitted none of its file-scope initialisers and
`shared_c_from_data()` returned NULL. The row had been failing from the day it
was written while printing green. Fixed in `9b6ca0475`.

The log tail here is that exact failure, not a lookalike: the `Segmentation
fault` is `strcmp(NULL)` in the dlopen host, and it is the LOUD failure standing
in front of the quiet one — which is why the host now checks `d()==NULL`
explicitly and prints `data=(null) -- file-scope initialisers did not run`.

**Ancestry, which is what makes this an identity and not a resemblance:**

    7d1aed2b5 (disclosure)  IS an ancestor of the sampled c1f7471fe
    9b6ca0475 (the fix)     is NOT an ancestor of c1f7471fe

So T sampled strictly inside the red window. Nothing to bisect and nothing to
revert.

**On the green being real rather than skipped:** the failing row sits behind
`@if command -v gcc`, so a box without gcc reports zero mismatches by skipping.
Checked: `gcc` is present, the skip branch's distinct string (`gcc not
installed; C shared-library check skipped`) is absent from the run, and the
success echo is `&&`-gated on `expect_same.sh` itself — so the echo appearing
proves both that the guard was taken and that the comparison passed.

**Residual, owned and already filed** — `--emit-obj` has the same defect through
a different mechanism (an object linked into a gcc-built program has no pxx entry
stub to ride, and needs `.init_array` in the relocatable writer):
`bug-a-c-an-emit-obj-object-linked-into-a-non-pxx-program-never-runs-its-initialisers`,
p55, unclaimed. That is a separate writer and a separate commit; it is not this
ticket.
- 2026-09-01 — resolved, commit 9d183dea9.
