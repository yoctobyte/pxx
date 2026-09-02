---
prio: 70
track: C
summary: "RESOLVED — one cause, five jobs: glib's headers call `__builtin_constant_p`, which the C frontend did not have, and 00ab464bf's `__GNUC__ 2.7` claim is what made glib reach for it. Re-laned P->C (the P guess came from the .pas in the failing step; the defect is in the C frontend). Fixed by reducing the builtin to the integer literal 0 beside __builtin_expect — the arm every non-GCC compiler takes. All five GREEN under testmgr, which owns the recipe."
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_c_gtk_call.pas /tmp/test_c_gtk_call26`, which names `test/test_c_gtk_call.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_call.pas at 1236bf31f930 in step 1/2, `./compiler/pascal26 test/test_c_gtk_call.pas /tmp/test_c_gtk_call26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T23:24:59Z
- **Test source:** test/test_c_gtk_call.pas
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_c_gtk_call.pas`.
  ```
  ./compiler/pascal26 test/test_c_gtk_call.pas /tmp/test_c_gtk_call26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_call.pas'` at 1236bf31f93084fe322e626880cc6132a33cf64a

## Range
> **The named sha `1236bf31f930` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1236bf31f930`, last good `ba98601dd917`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:311: error: call to undeclared function: __builtin_constant_p
(tail)
pascal26:311: error: call to undeclared function: __builtin_constant_p
  near:  __builtin_constant_p   str  >>>   str 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED (frankZ, plexus, 2026-09-02) — one cause, five jobs

All five `test_c_gtk*` reds are **one line**, identical in every ticket:

```
pascal26:311: error: call to undeclared function: __builtin_constant_p
  near:  __builtin_constant_p   str  >>>   str
```

That is `/usr/include/glib-2.0/glib/gstrfuncs.h:311`:

```c
if (__builtin_constant_p (!str) && !str)
```

…and :314, :160, :184, and `gstring.h:74` are the same builtin in the same two
shapes (`&&`-guard and ternary).

## Why it appeared, and why it is not a revert

`00ab464bf feat(C,B): the C frontend announces GNU C 2.7` is an ancestor of the
tested sha, and **its own header lists `__builtin_constant_p` among the builtins
that do not work** — the 2.7 version was picked precisely to keep 3.x/4.x-gated
builtins off. The rung was on the wrong side of the line: `__builtin_constant_p`
is a **2.x** builtin, so glibc and glib reach it on a bare `__GNUC__ >= 2` gate.

That commit fixed a SILENT wrong layout (`__attribute__` expanding to nothing,
so PACKED/ALIGNED did nothing) and its stated cost was loud compile failures
naming the construct. This is that cost arriving, and that commit's own answer
applies unchanged: **support the construct, do not claim a smaller version.**
Not reverted, not down-versioned.

## The fix, and what it is not

`__builtin_constant_p(x)` reduces to the integer literal **0**, beside
`__builtin_expect` in `cparser.inc`'s builtin arm. It is a REDUCTION, not an
implementation, and the comment says so: every use picks between an arm valid
only for a constant and a generic arm valid for anything, so 0 takes the generic
arm — the arm a compiler without the builtin takes anyway. There is no shape
where 0 yields a wrong VALUE, only a slower one. The argument is discarded,
which is also gcc's rule: it is unevaluated, so `__builtin_constant_p(strlen(str))`
must not call `strlen`.

**The one shape 0 is wrong for** (frankD): `BUILD_BUG_ON(!__builtin_constant_p(x))`,
which asserts x IS constant. 0 turns that into a negative array dimension — a
hard error, not a wrong value, so it stays on the loud side. Named in the source
comment so nobody rediscovers it. `__builtin_choose_expr` is still absent.

## Verification

Binary `7ef59bc560b4b9fc`, `converged after 1 round(s)`, at commit
`cd36a4595` plus this change.

```
test/test_c_gtk.pas         testmgr: GREEN
test/test_c_gtk_call.pas    testmgr: GREEN
test/test_c_gtk_types.pas   testmgr: GREEN
test/test_c_gtk_window.pas  testmgr: GREEN
test/test_c_gtk3_stock.pas  testmgr: GREEN
```

Run through `testmgr --job`, which owns the recipe — three of the five run under
`xvfb-run` and one greps `readelf -d` for `libgtk-3.so.0`, none of which a
hand-rolled comparison would have done. Row count asserted at 5.

**Positive control:** all five reproduced at binary `23e9a1d6a3775ac2` before
the change, rc=1, same error line. A green run here cannot be a run that did
nothing.

## Sequenced with frankD

frankD owns `00ab464bf` and had uncommitted `cparser.inc`/`defs.inc`/`ir.inc`
work in a different region; told, not asked, and landed after theirs. Their
note, kept because it bounds this claim: the builtin *declaration* is one
failure and the dead arm it guards *surviving* is a second — their const-branch
fold is what makes `if (__builtin_constant_p(x) && ...)` actually disappear once
the builtin reduces to 0. Only the first was mine. All five of these are green
without the second, so it does not bite here.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5cc4af7da.
