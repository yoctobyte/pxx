---
prio: 70
track: C
status: done
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

## ROOT-CAUSED AND FIXED (2026-09-01, frankC)

Not a test-cjson defect, and **not a defect in the failing step the auto-filer
named** — that step is the recipe's SKIP guard, which is where the bisect
attribution landed, not where anything went wrong. The lane guess of C was
right by accident: the bug is in the C frontend, but in `ParseCDeclType`, which
no line of this job's recipe mentions.

**A `void *`-returning callback's call signature carried a SIGNED 4-BYTE return
type.** `ParseCDeclType` sets `Result := tyInteger` as a placeholder for a
`void` base — its own comment says *"pointer suffix overrides below"* — and the
star loop does override it to `tyPointer`. The fn-pointer branch then
re-applied the placeholder, **overriding the override**.

Latent for as long as it existed, because nothing read that type: the pointer
travelled through RAX untouched and was right by accident. It turned fatal at
`e5a21152b`, where the indirect cdecl arm learned to widen a 32-bit signed
return — correct in itself, and still correct — read the wrong type, emitted
`cdqe`, and truncated every pointer such a callback handed back:

```
lua_newstate: the allocator returned 0x71a3aa200008, the caller saw 0xffffffffaa200008
```

lua's allocator is exactly `void *(*)(void *, void *, size_t, size_t)`, so
`luaL_newstate` segfaulted on the block it had just been given. Six lua
programs produced **no output at all**, which the harness's `2>/dev/null`
turned into an empty diff rather than a crash message — the failure looked like
wrong output for a day.

Fixed by qualifying the void test with pointer depth, which is the predicate
this file already uses for the cast case at line ~3431:

```pascal
if isVoid and (CTypePtrDepth = 0) then fpRet := tyInteger;
```

Regression test `test/cfnptr_void_pointer_return.c`, wired into `test-core`.
It asserts the fitness of its own subject: a 32-bit truncation is invisible
against an address below 4GB, and my first version used a `static` buffer and
passed on a compiler I already knew was broken. Positive control measured — the
unfixed compiler exits 3 with `void* callback returned 0x40a00008, want
0x7dea40a00008`.
- 2026-09-01 — resolved, commit PENDING-COMMIT.

## SCOPE OF THE VERIFICATION — THIS ONE WAS NOT RUN

**`test-cjson` was never executed against the fix.** There is no
`library_candidates/cjson` tree on this box, so the row SKIPs here and reports
success regardless of the compiler — it cannot tell me anything, and the box
that filed this regression is not the box that fixed it.

What IS verified:

- the root cause, at the source, with a positive control (the unfixed compiler
  exits 3 on `test/cfnptr_void_pointer_return.c`);
- `test-lua`, which failed the identical way — six programs, no output at all —
  and now passes 6/6;
- all four declarator spellings of a `void *` fn-pointer.

What is INFERRED: that cJSON's failure had this cause and only this cause.
The inference is strong — cJSON's allocator hooks are
`void *(*malloc_fn)(size_t)`, exactly the shape, and the reported failure was
the same empty-output signature as lua's — but it is an inference, and a second
cause hiding behind the first is precisely the pattern that produced three
separate findings in this repo in two days.

**Whoever next runs `test-cjson` on a box that HAS the tree owns the residual
question.** If it is still red, this ticket closed early and the right move is
to reopen it rather than to file a new one, because the two would describe the
same symptom.
