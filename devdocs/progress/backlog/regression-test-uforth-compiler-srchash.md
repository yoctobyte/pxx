---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `if [ ! -f "/home/rene/projects/uforth/uforth.py" ]; then \ echo "test-uforth: SKIP — no uforth tree at /home/rene/projec`. The job's own `src` (`tools/compiler_srchash.sh`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-uforth#src:tools/compiler_srchash.sh@3 at 82e070429d30 in step 2/2, `if [ ! -f "/home/rene/projects/uforth/uforth.py" ]; then \ echo "test-uforth: SKIP — no uforth tree at /home/rene/proje…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-13T22:50:31Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint
- **Failing step:** line 2 of 2 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  if [ ! -f "/home/rene/projects/uforth/uforth.py" ]; then \ echo "test-uforth: SKIP — no uforth tree at /home/rene/projects/uforth (git clone git@github.com:yoctobyte/uforth /home/rene/projects/uforth)"; \ exit 0; \ fi; \ wd="$(mktemp -d)"; \ trap 'rm -rf "$wd" "/home/rene/projects/uforth"/tests/_pxx
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-uforth#src:tools/compiler_srchash.sh@3'` at 82e070429d309766a5524b13c5e466a0d29246c6

## Range
bad `82e070429d30`, last good `e7a21f9b1fd8`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
self-host fixedpoint: verified — 1 round(s), 8a947b659a29 (stamp read back; sources match it)
compiling uforth.py as Nil-Python ...
test-uforth: smoke PASS — compiles, STD.UFO loads, native + PYTHON-bodied words evaluate
running uforth's own corpora, DIFFERENTIAL against CPython ...
running the Forth 2012 / ANS suite per WORD SET, DIFFERENTIAL against CPython ...
Segmentation fault
  DIFF word set coreplustest.fth
--- /tmp/testmgr-scratch-1835699/tmp/tmp.wdjlvQrkif/c.out	2026-09-14 00:50:08.920920598 +0200
+++ /tmp/testmgr-scratch-1835699/tmp/tmp.wdjlvQrkif/p.out	2026-09-14 00:50:23.376685367 +0200
@@ -40,7 +40,4 @@
 --- End of Preliminary Tests --- 
 
 Test utilities loaded
-*********
-You should see 2345: 2345
-******
-End of additional Core tests) CR
\ No newline at end of file
+*******timeout: the monitored command dumped core
test-uforth: FAIL — 1 of 1 corpora differ from CPython

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
