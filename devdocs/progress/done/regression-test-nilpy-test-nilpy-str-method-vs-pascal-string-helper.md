---
prio: 70
track: P
summary: "NOT a NilPy defect and not a too-broad str-method guard: `f0aca9c59` gave FindHelperForType a visibility test where it had had NONE (a flat scan in which any helper anywhere answered), and the test was reading that. Its precondition -- `import 'strhelperprobe.pas'`, a unit whose `uses sysutils` was believed to put TStringHelper in scope for the importing module -- was never true scoping: a unit's `uses` does not re-export to its consumers, in fpc or here. So `label.Trim()` stopped finding the Pascal helper and fell through to the Python str table, which correctly refuses it. ATTRIBUTED BY BUILD, NOT BY PLAUSIBILITY: the row passes at f0aca9c59^ (compiler 417ee5636a72) and fails at f0aca9c59 (compiler eb141da06a89), both measured by checking out compiler/ at each sha and rebuilding. Fixed by making the module import sysutils itself; all seven rows match, gate quick GREEN. The guard is unchanged and both negative arms still reach the helper, so the too-broad-guard control the test exists for is intact."
status: done
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26`, which names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy at 4d018b041297 in step 1/2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  **RESOLVED 2026-09-09 by frankS** — see the summary and the section at the end.
- **Found:** 2026-09-09T09:28:31Z
- **Test source:** test/test_nilpy_str_method_vs_pascal_string_helper.npy test/test_nilpy_str_method_vs_pascal_string_helper.expected
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy'` at 4d018b0412976d19045ab9e9ce1a1bb09059728c

## Range
> **The named sha `4d018b041297` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4d018b041297`, last good `06e404587e29`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:50: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
(tail)
pascal26:50: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
  near:   return label . Trim >>> ( )  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RE-LANED N -> P, 2026-09-09 (frankB) — the failing step is a NilPy file and the cause is not

`track: N` here is the watcher's FALLBACK, guessed from the failing step's
filename, and CLAUDE.md says in as many words that an auto-filed regression's
track is a fallback rather than a finding. The test is a `.npy`; the defect is
not in the NilPy frontend.

**What the test asserts** is that a Pascal type-helper method reached through
`import 'strhelperprobe.pas'` still resolves for a `str`-typed receiver —
`label.Trim()`, where `Trim` comes from `sysutils` and is deliberately NOT a
Python str method. It is the NEGATIVE arm of that test, present so a str-method
guard that is too broad cannot pass unnoticed. It now fails as
`unsupported str method .Trim()`, i.e. the helper is no longer reachable and the
str-method path claims the call instead.

**That is unit/scope resolution, which is Track P.** The range the watcher
records is `06e404587e29..4d018b041297`, and it contains
`f0aca9c59 fix(P): a generic routine's body resolves names as its declaring
unit` — a change to which unit's scope a body resolves names in, which is
exactly the mechanism a helper imported into a NilPy module depends on.
`1c16d4523` and `2049595a3` are in the same neighbourhood.

**Not a bisect — a reading of the range plus the subsystem.** Recorded so
whoever picks it up starts at the scoping change rather than at the NilPy
frontend.

**Confirmed present independently of anything in flight here:** the PINNED
compiler compiles this test and `compiler/pascal26` at `fedb492f9` does not,
with no local changes applied.

**How it nearly misled me, which is worth one line:** it went red in my second
nilpy tier run and green in my first, with my own frontend change in between, so
it read as mine. It was not — the discriminator is that I PULLED between the two
runs, and the tree moved. CLAUDE.md carries the case where a pull IMPROVES a
number you did not earn; this is its mirror, where a pull worsens one and the
obvious suspect is your own diff. I reverted a good change on that reading
before re-checking. Attribute a tier delta to a RANGE before attributing it to
yourself.

## 2026-09-09 (frankS) — attributed by build, and the test's premise was the defect

**The lane guess was right for the wrong reason, and the re-lane was right for
the right one.** `track: N` came from the failing step's filename, which is the
documented fallback. frankB re-laned to P on the reasoning that the mechanism is
Pascal helper scope. That reasoning holds, and the measurement now says so.

**The range had two buildable commits, so the bisect is one build.**
`06e404587e29..4d018b041297` is 15 commits and 13 of them are docs or tstate;
only `1c16d4523` and `f0aca9c59` touch the compiler, and nothing between them
does, so `1c16d4523`'s tree IS `f0aca9c59^` for this purpose.

| tree | compiler | row |
| --- | --- | --- |
| `git checkout 1c16d4523 -- compiler/` | `417ee5636a72` | **passes, byte-identical to .expected** |
| `git checkout f0aca9c59 -- compiler/` | `eb141da06a89` | `unsupported str method .Trim()` |

**The mechanism, from `PXXDBG=p.helper` (added in this commit).** The failing
lookup prints
`row=111 tk=23 rowunit=641 curunit=-1 visible=0` — the helper row is
sysutils', the scope asking is the main PROGRAM, and `DeclVisibleSect` says no.
Correctly: the module imports `strhelperprobe.pas`, whose `uses sysutils` does
not re-export to its consumers. Before `f0aca9c59`, `FindHelperForType` had no
visibility test of any kind, so any helper anywhere answered and the test read
that as "in scope".

**So the fix is the test's precondition, not the guard.** The module imports
sysutils itself; all seven rows match and gate quick is GREEN. `PyStrMethodOwnsMember`
is untouched, and both negative arms (`Trim`, `IsEmpty`) reach the Pascal helper
again — which is what keeps the four positive arms from being a guard that
cannot fail.

**Not a regression to revert.** `f0aca9c59` made helper lookup more correct;
what broke was a test asserting a scoping accident. Its own comment, and
`strhelperprobe.pas`'s, both stated that accident as the premise, and both are
corrected in place rather than left to be read as verified.
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9b4146700.
