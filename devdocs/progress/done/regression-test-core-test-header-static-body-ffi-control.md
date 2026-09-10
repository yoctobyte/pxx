---
prio: 70
track: A
status: done
owner: frankB
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

## RESOLVED 2026-09-10 by frankB — my change, my regression, and the repair is TWO rows

frankH's triage is correct in every part and I am not re-deriving it. Confirmed:
the culprit is `e53eff428` (mine), not `7e4f69a34350`; the lane is A, not P; and
the killed row is a POSITIVE CONTROL rather than a feature test.

### What broke, and why the obvious repair is wrong

`e53eff428` made the compiler refuse a soname it DERIVED from a header's file
name when this host cannot resolve it. `hdrstatic_ffi.h` asks for exactly that
shape on purpose, so the refusal is correct and it took the control with it.

The tempting fix is to make the test expect the error. That clears the red and
leaves the two `no invented soname` assertions above it standing on nothing —
which is the failure the control was built to prevent in the first place. The
recipe had already called it: *"one refactor from being rows that cannot fail."*
This was that refactor.

### The question split in two, so the control did

The old row answered both halves at once, and only one half survives the change.

| half | question | now answered by |
| --- | --- | --- |
| 1 | is the derived-soname path LIVE — would a regression be seen? | `test_header_static_body_ffi_control.pas`, asserting the REFUSAL and that the diagnostic names `libhdrstatic_ffi.so` |
| 2 | can `readelf -d \| grep lib<stem>.so` match AT ALL on this compiler? | `test_header_static_body_ffi_control_explicit.pas`, new, via an EXPLICIT `external` clause |

**Half 1 is better aimed than what it replaced.** The old row inferred that the
soname-inventing machinery was running by finding its output in an ELF; this one
reads it off the compiler, which NAMES the invented soname. And it records
something the ticket did not know: the regression these rows guard now stops at
COMPILE time. Measured 2026-09-10 — a header with a bare declaration whose stem
is `hdrstatic` is refused with `die at exec: hs_declared is imported from
libhdrstatic.so`. So if a static body were dropped and imported again,
`test_header_static_body.pas` fails to BUILD, naming the library, before any grep
runs. The greps are now the second net, not the first.

**Half 2 is frankH's suggested shape, and it was a guess that measured out.**
An explicit `external 'libhdrstatic_ffi.so'` still emits the dangling DT_NEEDED:
one match, verified. It is the right instrument for this half precisely because
`e53eff428` does not touch it — a soname the user WROTE is intent, and the
refusal is scoped to names the compiler invented. Same route `test_c_argspill`
and `test_c_lazycasing` already depend on.

### Both rows mutation-tested, because a control that cannot fail is the bug here

Asserting they pass proves nothing about rows whose entire job is to be able to
fail. So each was run against a mutant:

| row | mutant | result |
| --- | --- | --- |
| half 1 | the PINNED compiler, which predates the guard | **FAIL**, rc=0, "did not refuse libhdrstatic_ffi.so" |
| half 2 | same source with the CALL removed, so nothing references the extern | **FAIL**, no DT_NEEDED |

The pin being pre-guard is what made half 1's mutation free — no rebuild, no
revert. Worth noting for the next person: the original comment says a pre-fix
compiler was no longer available for the OTHER fix, and that is still true; it is
only my guard the pin predates, and it will stop predating it at the next pin.
**When that happens, half 1's mutation needs a real revert-and-rebuild.**

### Not changed

The two `no invented soname` assertions and the three `expect_same` rows are
untouched and still pass. Nothing about `e53eff428`'s refusal is being softened:
a build that dies at exec is worth refusing, and frankH's read that the refusal
itself looks correct is the one I agree with.
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
