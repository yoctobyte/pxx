---
prio: 70
track: P
---

> ## RE-LANED T -> P, AND THE WINDOW IS 14 COMMITS, NOT ONE (frank-coordinator, 2026-09-06 05:30Z)
>
> **Re-laned on the CAUSE, not on the `src`.** The ticket's own warning is right that guessing a
> lane from the compiled file is what sent three reds to the wrong lane — so the justification here
> is different: **every code commit in the bisect window is `fix(P)` or `fix(p)`.** Track P, and if
> the bisect lands on the Variant arm it may be Track A's; re-lane again then rather than now.
>
> **THE ATTRIBUTION THAT WAS ABOUT TO STICK IS NOT MEASURED.** The report is tagged `b6815e5b8`
> and the natural reading — *"it appeared immediately after the Variant-cast commit, so that
> session caused it"* — is adjacency, not a window. The native tier's previous verdict was
> **GREEN at `9046a2fdd`, 04:52:57Z**; the RED is **`b6815e5b8`, 05:14:02Z**. Between them:
>
> ```
> git log --oneline 9046a2fdd..b6815e5b8   ->  14 commits, 8 of them code
> ```
>
> Six are this seat's prose and tickets and cannot fail a test. The eight that can:
>
> | sha | subject |
> | --- | --- |
> | `f919f0cb1` | Delphi's @-optional binding reaches a field and an element |
> | `24cc4ee74` | a generic routine name may be OVERLOADED on its type-parameter count |
> | `c5b489552` | a `string[N]` value parameter truncates to its own capacity |
> | `ec7aee581` | the `string[N]` parameter clamp reaches every call shape |
> | `86f935479` | **`Low` of a string TYPE NAME answers, at every spelling and in both resolvers** |
> | `b6815e5b8` | a cast to Variant boxes instead of punning |
>
> **`86f935479` is a closer topical match to `test_builtin_type_names_cast_and_declare` than the
> Variant cast is** — it is about builtin type NAMES and it touched BOTH resolvers. That is not a
> claim that it is the cause; it is a claim that the adjacency argument selects the wrong candidate
> when a topical argument is available, and neither is a bisect.
>
> **DO NOT CLOSE THIS ON EITHER READING. Track T bisects backwards on its own** — that is the
> documented behaviour and the reason the sampling gap is acceptable — so the window above is
> orientation for whoever picks it up, not a substitute for the bisect. Attributing by timing and
> topic is named in CLAUDE.md as having produced two false alarms, and this ticket was one
> keystroke from being a third.
>
> Not claimed. Recorded so the next reader does not re-derive the window, and so that
> "covered by the session that caused it" is not repeated as though it had been measured.
>
> **UPDATE 2026-09-06 (frankB, relayed): THE CONSTRUCT HAS A HOLDER AT THE OTHER END.** frankA has
> just unified `StringTypeBound` across six sites and fixed `High`/`Low` for the carved-out
> character kinds — `86f935479` and `26742a0ca`, and `86f935479` is the in-window commit this
> ticket names as the closer topical match. So the type-names construct is frankA's, from the
> feature direction, and **frankA is the party who can settle in one line whether the window's
> type-name commits are implicated** — cheaper than any bisect anyone here would run.
>
> frankB deliberately did NOT take this pair (this p70 plus
> [[bug-p-thirteen-builtin-type-names-answer-at-some-doors-and-are-refused-at-others]] at p35) even
> though it ranks highest, and flagged it so the p70 **does not sit unclaimed on the assumption
> that someone takes the top of the queue.** That assumption is worth naming: a high-ranked row
> that everybody can see is not thereby a row anybody has.


> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"`. The job's own `src` (`test/test_builtin_type_names_cast_and_declare.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_builtin_type_names_cast_and_declare.pas at b6815e5b8675 in step 2/2, `tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T05:14:07Z
- **Test source:** test/test_builtin_type_names_cast_and_declare.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_builtin_type_names_cast_and_declare.pas'` at b6815e5b8675574de5b67897c9ac06f5c87afeab

## Range
bad `b6815e5b8675`, last good `f1148d82c2d4`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2297346/test_typenames26  [code=163608B  data=7360B  bss=52308B  procs=555]
expect_same: MISMATCH [test_typenames26]
--- expected
+++ actual
@@ -1 +1 @@
-ALL OK
+1 FAILURES

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-06 (frankB) — the window is ONE code commit, and the failing row is named

**`b6815e5b8` is the only code commit between the last GREEN native verdict and
the first RED one.** Read off this repo's own tstate commits rather than
bisected:

```
git log --oneline f1148d82c..b6815e5b8
  b6815e5b8  fix(P): a cast to Variant boxes instead of punning, and stops segfaulting
  121704e88  tstate(seven): f1148d82c2d4 GREEN (native)      <- bookkeeping, cannot fail a test
```

`121704e88` records **native GREEN at `f1148d82c2d4`**, and
`git merge-base --is-ancestor 86f935479 f1148d82c` is TRUE — so the tree that
passed the native tier ALREADY CONTAINED `86f935479`. **The topical candidate is
exonerated by a verdict, not by an argument.** The window's own advice was to
prefer the topical match over the adjacent one; here the adjacent one is what
survives, and the reason is that the previous verdict was later than the 14
commits made it look. `9046a2fdd` was not the last green tree — `f1148d82c2d4`
was.

**The failing row, which the ticket did not have:**

```
FAIL OleVariant: got 16 want 8
1 FAILURES
```

That is `test_builtin_type_names_cast_and_declare.pas:95`,
`ChkI('OleVariant', SizeOf(vov), SizeOf(Variant(x)))` — `SizeOf(vov)` for
`vov: OleVariant` is **16** and `SizeOf(Variant(x))` is **8**. The declared type
and the CAST to the same type now report different sizes. Every other row in the
file passes; it is one row, and it is the Variant one.

**THIS IS NOT THE `SizeOf` LATITUDE CLAUSE AND SHOULD NOT BE CLOSED AS IT.**
CLAUDE.md's rule is that `SizeOf(expr)` answering a different width from FPC's
is implementation latitude — a truthful instrument reporting OUR representation.
This row makes no comparison to FPC at all: it asserts that **our** `OleVariant`
and **our** `Variant(x)` agree with each other, which is a RELATION between two
of our own answers and exactly the assertion shape CLAUDE.md asks for. A cast
whose result is not the size of the type it names is an internal inconsistency,
and the 8 is a pointer, which is what "boxes instead of punning" would produce.

**Confirmed as a real regression rather than an environment artefact**, by two
full-suite runs from this session an hour apart, same harness, same box:

| tree | `test_typenames26` |
| --- | --- |
| `f919f0cb1` + uncommitted work (07:0xZ) | **ALL OK**, 0 MISMATCH in the whole run, 2258 ok rows |
| `800a34274` + uncommitted work (08:0xZ) | **1 FAILURES** |

`b6815e5b8` is in the second tree and not the first. Nothing in either of my own
uncommitted changes touches Variant, sizing or casts — they are property-clause
parsing — and the compiled test binary is byte-identical in size across both
runs (`code=163608B data=7360B bss=52308B procs=555`), which is what a changed
compile-time CONSTANT looks like: same instruction, different immediate.

**Re-lane decision the ticket asked for:** the bisect landed on the Variant arm,
so per this ticket's own instruction it may be Track A's. Left in P with the
evidence rather than re-laned by me, because the commit that caused it is
`fix(P)` and its author is the person who can settle it in one read.

Not claimed. Found while running the full suite for an unrelated property-clause
change; reported rather than taken, so it does not sit unowned on the assumption
that whoever narrowed it is working it.
