---
prio: 70
track: C
status: done
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

## ROOT-CAUSED AND FIXED (2026-09-01, frankC)

Not a test-lua-cross defect, and **not a defect in the failing step the auto-filer
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
- 2026-09-01 — resolved by `f8d24acef` (the ParseCDeclType fix); moved to done/ in `695dd4183`.
