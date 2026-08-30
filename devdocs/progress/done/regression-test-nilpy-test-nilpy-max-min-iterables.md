---
prio: 70
track: N
status: done
owner: frankA
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (ValueError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 47 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_max_min_iterables.npy red at 0200df7eabcd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:33:24Z
- **Test source:** test/test_nilpy_max_min_iterables.npy test/test_nilpy_max_min_iterables.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_max_min_iterables.npy'` at 0200df7eabcd33796c0f7ac151b80aafbf75b5fb

## Range
> **The named sha `0200df7eabcd` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0200df7eabcd`, last good `3f854c927aac`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3750893/test_nilpy_maxmin_iter26  [code=1272141B  data=55351B  bss=53196B  procs=1860]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_max_min_iterables.expected	2026-08-29 16:03:42.850941360 +0000
+++ -	2026-08-30 02:08:28.243527547 +0000
@@ -3,13 +3,3 @@
 3 1
 z a
 none none
-b b
-3 1
-c a
-3 0
-99 97
-6 2
-9 2
-[1, 2] [3]
-7 3 2.5 a
-ValueError: max() iterable argument is empty

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution (frankA, 2026-08-30)

**Cause: `7b73a385d` (feat(N): list.sort(key=) — the callable→Pointer coercion),
inside the watcher's range and confirmed by bisect** — `7b73a385d^` prints `b`,
`7b73a385d` raises. Both builds seeded from their own committed stable and
fixedpoint-verified; see the seeding note below, which is why the first two
bisect attempts were void.

That commit moved the callable→Pointer coercion into `PyBindKwArgs`, i.e. into
the KEYWORD path. The coercion runs AFTER overload selection, so it made the
`key: Pointer` candidates *viable* for a keyword call — and therefore newly
reachable for receivers that cannot be walked as a list. A dict handle bound to
`max(l: TPyList; key: Pointer)` and was dereferenced as a `TPyList`:
`l.count`/`l.at` read a `TPyDict`'s fields, and the garbage surfaced far away as
`TypeError: expected a number, got object`. Before the commit these calls fell
through to the variant arm, which normalises through `pylist_v`.

The measured boundary is what named the mechanism: `max(d, f)` **positionally**
works and `max(d, key=f)` does not, and on the failing path the key function is
never called.

**Fix — complete the receiver set rather than special-case the dict.** `sorted`
has carried `TPyDict` and `AnsiString` overloads since
`bug-nilpy-sorted-over-a-string-segfaults`, whose comment records this exact
failure ("the AnsiString handle bound to the TPyList overload and was
dereferenced as an object"). `min`/`max` had only TPyList/TPyIter/TPyRange. Added
the two missing receivers, delegating to the TPyList routine (`d.keylist`,
`pystr_charlist(s)`) so the empty-sequence ValueError and the first-wins tie rule
stay in one place. No frontend file touched.

**A `Variant` keyed pair was written and then REMOVED — it bought nothing.** I
first read "tuple/generator now work" as its effect; that compared a *literal*
receiver before against a *named* receiver after, changing two axes at once. With
the pair deleted the whole suite still matches, so it is not in the change: an
overload that alters how a variant unwraps is exactly what the decl-order comment
above `min(it: TPyIter…)` warns about, and it has to earn its place.

**Gate:** `test_nilpy_max_min_iterables` matches its CPython-generated
`.expected`; the eight neighbouring sort/sorted tests still match; the shapes the
decl-order comment says broke historically (`min(v)`/`sum(v)` over a variant list,
2/3/4-arg numeric, `default=`) all match CPython. `make compiler/pascal26`
converged. Baseline re-run with `pyeval.pas` stashed fails — and note the compiler
binary is byte-identical with and without this change (`1ff8acbe123b`), because
`compiler/builtin/**` is consumed when compiling a `.npy`, not linked into the
compiler, which is what makes that baseline cheap and honest.

**The new rows needed their own baseline.** With the whole file, the baseline dies
on line 6 (the original row) and never reaches rows 16-20, so the file cannot show
they are load-bearing. Run alone against the baseline library: dict and named-str
fail, and **tuple/generator/list-of-lists already passed** — they are pinned as
guards, not claimed as fixes.

## Residual, filed separately — NOT closed by this

A **literal** str receiver with `key=` is still broken and is a regression from
the same commit (`max("bca", key=f)` printed `b` at `7b73a385d^`). A **named** str
works. The keyword promoter re-targets on the argument's STATIC type, and a
literal reaches no keyed overload, so this needs `pyparser.inc`, not the library.
A literal tuple/generator fails the same way but is *pre-existing* (broken at
`7b73a385d^` too) and is `bug-nilpy-keyword-arg-vs-overload-set`.
→ `regression-nilpy-a-literal-str-receiver-with-key-reaches-no-keyed-overload`

**Not a defect:** `max(d, f)` positionally answers `b` where CPython raises. NilPy
is upward-compatible one direction only; accepting what CPython rejects is a
divergence, not a bug (CLAUDE.md, Track N).

## Seeding note for the next bisect in this repo

`make compiler/pascal26` seeds from `./compiler/pascal26` — the binary already in
the tree. Walking backwards, that is the *previously tested* commit's binary, and
an older one fails with `undefined variable (__pxxblockmove)`. Seed each commit
from its OWN `stable_linux_amd64/default/stable_pinned`, `rm` the fixedpoint
stamp, `touch` the sources (a copied-in seed is newer than them — CLAUDE.md's
no-op trap), and require `converged after` in the log before accepting a verdict.
A plain `git bisect start` here also spans ~5600 commits, nearly all watcher
`tstate` publishes; path-limit it or test candidates directly.
- 2026-08-30 — resolved, commit f11128eaf.
