---
prio: 70
track: A
---

> **Track guessed as P from the FAILING STEP** — line 1 of 107, `./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ffi`, which names `test/test_header_static_body_ffi_control.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_header_static_body_ffi_control.pas at 7e4f69a34350 in step 1/107, `./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ff…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T10:47:04Z
- **Test source:** test/test_header_static_body_ffi_control.pas lib/crtl/src/string.c +2
- **Failing step:** line 1 of 107 of the job's recipe; it names `test/test_header_static_body_ffi_control.pas`.
  ```
  ./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ffi26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_header_static_body_ffi_control.pas'` at 7e4f69a343501a4b71ef7cfb5033e90fe5e4bcd5

## Range
bad `7e4f69a34350`, last good `e1ba463ce0c1`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: this build would die at exec: `hs_ffi_declared_only` is imported from libhdrstatic_ffi.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (hdrstatic_ffi.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
(tail)
pascal26:7: error: this build would die at exec: `hs_ffi_declared_only` is imported from libhdrstatic_ffi.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (hdrstatic_ffi.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
  near: hs_ffi_declared_only ( 1 ) ) ; >>> end . 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Triaged 2026-09-10 by frankH — NOT the tip commit, and the row it kills is a POSITIVE CONTROL

**Re-laned P -> A.** The auto-guess read the failing STEP, which names a `.pas`
file, and the change that caused this is in the shared FFI/soname resolution
(`compiler/pasparser_proc.inc`, `compiler/symtab.inc`, `compiler/defs.inc`).

**The culprit is `e53eff428`, not `7e4f69a34350`.** The watcher tagged the
range's tip, which was mine, and `git log -S'this build would die at exec' --
compiler/` names exactly one commit: *"fix(n): a header's file name is not its
library's name — resolve it, and refuse the guess when it cannot be"*, inside
the same 3-commit range. My two commits in that range are a unit-loader
deferral and a SizeOf refactor; neither is anywhere near soname resolution, and
the diagnostic text is that commit's own.

**THE IMPORTANT PART IS NOT THE RED ROW.** `test_header_static_body_ffi_control.pas`
is not a feature test — it is the POSITIVE CONTROL for the two soname-absence
assertions above it in the same Makefile recipe, and the recipe says so at
length: those two rows assert a DT_NEEDED pattern is ABSENT, "no match" is
indistinguishable from a grep that could never match, and this row exists to
prove the pattern CAN appear on the same compiler. It does that by compiling a
bare declaration reached through a header, whose derived soname
`libhdrstatic_ffi.so` deliberately does not exist — the recipe's own comment
reads *"NEVER RUN -- the binary cannot load"*.

`e53eff428` makes exactly that shape a compile ERROR. So the control cannot be
built, and **the two assertions above it are now rows that cannot fail** — which
the recipe had already flagged as one refactor away:

> *"Validating that in the other direction used to need a PRE-FIX compiler; the
> pin now postdates the fix, so that control had become uncheckable and the two
> assertions above were inherited-control rows: one refactor from being rows
> that cannot fail."*

That prediction has now come true, and it is what makes this worth more than a
red row: the new refusal is arguably CORRECT behaviour (a build that dies at
exec is worth refusing), so the tempting repair — make the test expect the
error — clears the red and leaves two silent assertions behind it. **Whoever
takes this owns finding the control a new body**, not just making the row
green. The diagnostic itself suggests the shape: an explicit `external
'<soname>'` clause naming a soname that does not exist would still produce the
dangling DT_NEEDED the control needs, without going through the derived-name
path the new check refuses.

Reproduced locally at `0dfa0b298`; unchanged.
