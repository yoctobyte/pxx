---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 2 of 2, `if [ ! -f "library_candidates/cjson/src/cJSON.h" ]; then \ echo "test-cjson: SKIP — no cJSON tree at library_candidates/`, which names `test/cjson/runner.c`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-cjson#src:tools/compiler_srchash.sh at e5a21152b5d1 in step 2/2, `if [ ! -f "library_candidates/cjson/src/cJSON.h" ]; then` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T05:58:19Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `test/cjson/runner.c`.
  ```
  if [ ! -f "library_candidates/cjson/src/cJSON.h" ]; then \ echo "test-cjson: SKIP — no cJSON tree at library_candidates/cjson/src (fetch cJSON 1.7.18 there to run)"; \ exit 0; \ fi; \ echo "compiling cJSON runner ..."; \ wd="$(mktemp -d)"; trap 'rm -rf "$wd"' EXIT; \ ./compiler/pascal26 -g -Ilib/crt
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-cjson#src:tools/compiler_srchash.sh'` at e5a21152b5d1d0d763b5b676110e4558978946e0

## Range
bad `e5a21152b5d1`, last good `a3b1af61a27f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
self-host fixedpoint: verified — 1 round(s), ea3bc3691cd1 (stamp read back; sources match it)
compiling cJSON runner ...
pascal26:5: warning: "/*" within comment
ok: /tmp/tmp.1iDnxyByZN/runner  [code=511768B  data=11072B  bss=326328B  procs=899]
test-cjson: FAIL floatarr.json
--- test/cjson/floatarr.expected	2026-08-29 16:03:42.642941363 +0000
+++ /tmp/tmp.1iDnxyByZN/got.txt	2026-09-01 05:56:42.032178973 +0000
@@ -1 +0,0 @@
-{"ratio":0.125,"delta":-0.0625,"list":[0.5,1.25,-3.75],"mixed":[1,0.5,2,-0.25]}
test-cjson: FAIL floats.json
--- test/cjson/floats.expected	2026-08-29 16:03:42.642941363 +0000
+++ /tmp/tmp.1iDnxyByZN/got.txt	2026-09-01 05:56:42.403186214 +0000
@@ -1 +0,0 @@
-{"half":0.5,"quarter":0.25,"neg":-2.75,"big":100.125,"tiny":0.001953125,"price":19.5}
test-cjson: FAIL nested.json
--- test/cjson/nested.expected	2026-08-29 16:03:42.642941363 +0000
+++ /tmp/tmp.1iDnxyByZN/got.txt	2026-09-01 05:56:42.762193221 +0000
@@ -1 +0,0 @@
-{"users":[{"id":1,"name":"alice","admin":true},{"id":2,"name":"bob","admin":false}],"count":2,"tags":["a","b","c"],"meta":{"nested":{"deep":[1,2,3]}}}
test-cjson: FAIL scalars.json
--- test/cjson/scalars.expected	2026-08-29 16:03:42.643941363 +0000
+++ /tmp/tmp.1iDnxyByZN/got.txt	2026-09-01 05:56:43.114200091 +0000
@@ -1 +0,0 @@
-{"id":42,"neg":-7,"name":"alice","ok":true,"bad":false,"nothing":null}
test-cjson: FAIL strings.json
--- test/cjson/strings.expected	2026-08-29 16:03:42.643941363 +0000
+++ /tmp/tmp.1iDnxyByZN/got.txt	2026-09-01 05:56:43.460206844 +0000
@@ -1 +0,0 @@
-{"esc":"tab\there","nl":"line1\nline2","quote":"say \"hi\"","back":"a\\b","empty":""}
test-cjson: FAILURES

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
