---
track: A
prio: 45
type: task
status: done
owner: frank3
---

# Carve NilPy's lvalue/member parsing out of `parser.inc` (split 2)

**Lane: this is Track A structural work, not deferred Track N work.** The shared
`parser.inc` is A's ground; the carve serves the owner's reduced-compiler ask and
deletes the bare-vs-selector double case that has already produced three bugs. The
standing mandate defers Track N *features and bugs* — NilPy-motivated is not
NilPy-owned, and A's own structure is not deferred by it.

## This campaign now has an objective finish line

Measured 2026-08-19 by
[[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]], which
tried to omit the NilPy frontend and could not:

> **176 NilPy symbols are still called from the shared `parser.inc`, at 426 sites.
> `-dPXX_NO_NILPY` compiling clean IS "carve complete."**

That is the property this campaign lacked. "Fewer guards" is a direction; a compiler
that builds without the frontend is a test. Heaviest remaining callers, i.e. the best
targets after this split: `PyParseBoolExpr` (23 sites), `PyCallMeth1` (19),
`PyAugBinTok` (12), `PyIsIdent` (9), `PyForceVariant` (9), `PyStoredName` (8),
`PyParseSliceTail` (8), `PyMakeDynAttrSet` (8), `PyHoistPark` (8).

Split 2 of the campaign opened by
`task-a-carve-nilpy-selectors-out-of-parser-inc`, which landed split 1
(`ParseClassRecordSelectors` → `PyParseClassRecordSelectors` in `pyparser.inc`,
0 regressions over the 513-file `.npy` sweep, self-host byte-identical). Read
that ticket's Progress section first — it records the method that worked and,
more usefully, the arms that are NOT safe to delete and why.

## Target

`ParseLValueAST`. It is the **sibling path** to the routine already split: a
bare-identifier receiver (`c.m`) goes through `ParseLValueAST`, and every other
receiver shape (`C().m`, `objs[0].m`, `a.b.m`) goes through
`ParseClassRecordSelectors`. Two parsers for one construct.

## Why this one, beyond the guard count

This split has a payoff the first one did not. The bare-vs-selector divide has
produced at least three separate bugs where one path learned something and the
other stayed broken — a class-attribute read through a non-bare receiver, a
bound-method value that segfaulted on a temporary receiver, and a chained
subscript that ignored its index (`project_nilpy_lvalue_vs_selector_path_must_both_know`,
`devdocs/dev/normalise-dont-special-case.md`). The recurring fix is "teach both",
which is exactly the thing nobody remembers to do.

Once BOTH selector paths are NilPy-only routines, they can share a NilPy-side
member-resolution helper — which is the real fix for the double case. That is
impossible while each is entangled with the Pascal arm it sits next to. So the
carve is not only hygiene here; it is the precondition for deleting the double
case.

## Method (proven by split 1)

1. Copy the routine into `pyparser.inc` under a `Py`-prefixed name.
2. Dispatch to it from the top of the Pascal original on `PyExprMode`, so every
   call site is untouched.
3. In the copy, fold `PyExprMode` / `isNilPy` / `NilPyUserCode` to `True` — this
   is provable (`PyExprMode` is set only by `pyparser.inc`), which keeps the
   split a pure restructuring with no reachability change in either dialect.
4. In the Pascal original, delete **only** the `PyExprMode`-guarded arms. Do NOT
   delete `isNilPy` or `NilPyUserCode` arms: with `PyExprMode` false they are
   still reachable — `isNilPy` holds while parsing the Pascal RTL units an
   `.npy` program pulls in, and `NilPyUserCode` reduces to
   `isNilPy and (CurrentUnitIdx < 0)`, true during the main program's
   pre-`PyExprMode` phase. Deleting them is a behaviour change wearing a
   refactor's clothes.
5. Prune variables the deletions orphaned, or FPC's `-vw` will say so.

## Gate

`make compiler/pascal26` (the fixedpoint — the strong oracle for the Pascal
half) + `tools/gate.sh quick` + a whole-suite HEAD-vs-pinned `.npy` sweep
(`/tmp/sweep/regress.sh`; recreate from split 1's ticket if gone). The sweep is
not optional here: a carve-out is a NARROWING change and cannot be
regression-tested by the tests that motivated it. Also run the FPC seed build by
hand — adding a routine is not covered by `make` or `gate.sh`.

## After this

Remaining `parser.inc` guard counts to drive down: `PyExprMode` 125, `isNilPy`
67. Some are genuinely shared (a NilPy-only *diagnostic* on a shared construct);
the test is whether the two dialects want different SEMANTICS, not merely a
different message.

## Progress — DONE 2026-08-19 (frank3)

Landed as three commits, deliberately: a verbatim copy is provably mechanical
and the fold is where the thinking is, so a regression can be attributed to one
or the other by bisecting two commits instead of reasoning about one.

| step | commit | what |
| --- | --- | --- |
| 1/3 | `fd6ec21a3` | verbatim copy → `PyParseLValueAST` in `pyparser.inc` (3145 lines), dispatch on `PyExprMode` at the top of the Pascal original |
| 2/3 | `832a42d02` | fold `PyExprMode` (29 sites) / `isNilPy` (15) / `NilPyUserCode` (5) in the copy; delete the Pascal-only scalar-member refusal |
| 3/3 | `2730e6566` | delete the 29 dead `PyExprMode` arms from `parser.inc` (−634 lines) |

`ParseLValueAST` in `parser.inc`: **3145 → 2511 lines**. The `isNilPy` /
`NilPyUserCode` arms were left in place there, per the method's step 4.

### The fold was provable, and here is the proof, since step 3 rests on it

`PyExprMode` is written at exactly five places (`parser.inc`'s
`ParseUsesUnitBody`, four in `pyparser.inc`) and **every one is
save/restore-balanced**, so nothing reachable from this routine can flip it and
observe the change. `isNilPy` is set once from the input filename.
`NilPyUserCode` is `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`
(`symtab.inc:25`), which reduces to `isNilPy` when PyExprMode holds — the
OPPOSITE reduction from the Pascal side, which is exactly why those arms stay
there.

### Correction to the finish line above — it is further away than it looks

Counting `Py*` routines whose **bodies** are in `parser.inc`, and the sites
referencing them, with comments and string literals stripped:

| | Py* bodies in `parser.inc` | sites |
| --- | --- | --- |
| before the carve | 183 | 569 |
| after split 2 | 183 | 504 |

**Moving 3145 lines of the single most dialect-forked routine out of the shared
file removed no `Py*` helper from it at all, and 11% of the sites.** The
remaining work is therefore *not* more big forked routines — it is the 183 `Py*`
HELPERS whose bodies still sit in `parser.inc`. Those are what `-dPXX_NO_NILPY`
trips over, so they are what the finish line actually measures. Whoever takes
split 3 should target helper bodies, not another fork site, or the metric will
not move.

(This method gives 183/504 where the campaign's opening measurement recorded
176/426 — the same population under a different counting rule. I did not
reproduce that figure and am not claiming to; what is comparable is the
before/after pair above, both taken with the same script.)

Remaining raw guard counts in `parser.inc`: `PyExprMode` 130, `isNilPy` 79
(these count comment mentions too, unlike the table).

### Gate actually run

`make compiler/pascal26` fixedpoint converged in 1 round at every step;
`make bootstrap` (FPC seed → build → verify, byte-identical) — its `-vw` notes
are what found the 18 orphaned locals; `tools/gate.sh quick` GREEN at each
step; seven NilPy repros named one by one, chosen to hit the folded arms
(`property`, `bound_method_value_receiver_shapes`,
`augmented_subscript_index_once`, `augmented_subscript_variant_base`,
`attr_off_subscript_of_call_result`, `str_chars_through_a_variant`,
`annotated_class_attribute`) all match `.expected`.

**The whole-suite `.npy` sweep in the Gate section above was NOT run**, and the
line is superseded: `.claude/hooks/no-full-suite.sh` refuses it, and CLAUDE.md's
per-fix loop supersedes ticket `Gate:` lines that name long local suites
(`decide-gate-line-convention`). The escape exists but a peer cannot authorise
it and the owner did not ask. NilPy breadth for this change is Track T's, which
is UP and now running full tiers ~1h behind HEAD; step 2 already came back
GREEN native (`tstate/832a42d026cd`).

## Log
- 2026-08-19 — resolved, commit 86d2fe061.

---

## Split 3 — ParseFactorCore (2026-08-19/20)

The heaviest remaining fork site, carved with the same three-commit shape.

| step | commit | what |
| --- | --- | --- |
| 1/3 | `f380d7cd0` | verbatim copy → `PyParseFactorCore` in `pyparser.inc` (6768 lines), dispatch on `PyExprMode` at the top of the Pascal original |
| 2/3 | `ec33f4e5e` | fold the 95 code-level guards in the copy (43 `PyExprMode`, 52 `isNilPy`/`NilPyUserCode`) → zero |
| 3/3 | `3c8ec4c7d` | delete the dead `PyExprMode` arms from `parser.inc` (−764 lines) |

`ParseFactorCore` in `parser.inc`: **6786 → 6022 lines**; `PyExprMode` in it
**43 → 1** (the dispatch); whole file **36354 → 35590** lines and `PyExprMode`
**119 → 77**.

**The `isNilPy` / `NilPyUserCode` arms stay on the Pascal side, and this is not
an omission.** `parser.inc` still runs during a NilPy compilation — for the
Pascal units a `.npy` program pulls in — where `isNilPy` is True and
`PyExprMode` is False. `NilPyUserCode` is a *function* (`symtab.inc:25`),
re-evaluated at every read, so there is no cached-value hazard in either
direction. It is the opposite reduction from the pyparser side: stage 2 folded
all 52 there, stage 3 folds none here. Any future split inherits this rule.

### Corrected measurement — the figures in `f380d7cd0` are superseded

`f380d7cd0`'s message reported "ParseFactorCore: 94 distinct pyparser routines,
160 sites, 109 forks; parser.inc total: 182 distinct, 475 sites, 207 forks; 34%
of the surface". **Those numbers are wrong** and the commit is pushed and left
as written. Two defects in the measuring script, in sequence:

1. the stripper did not preserve newlines (36355 → 27698 lines) while the caller
   located routine boundaries in the RAW file and sliced the STRIPPED text, so
   every per-routine figure named the wrong region of the file;
2. the replacement stripper preserved lines but did not implement **nested**
   comments, which `lexer.inc:663` enables by default. A `{code, recv}` inside a
   brace comment at `pyparser.inc:40278` desynced the scan across ~1000 lines.

Both tells were **arithmetic impossibility**, not implausibility — a stripped
count exceeding the raw count. That is what makes them cheap to catch and worth
looking for: *check the instrument, not the output*, because a defect like this
produces perfectly plausible numbers for every routine it does not happen to
break. The working stripper is lexer-accurate (NestedComments on; `{}` nests on
`{}` only, `(* *)` on `(* *)` only, no cross-nesting) and asserts line-count
preservation and stripped ≤ raw on every run.

Counting rule for everything below: bare-identifier occurrences over
comment-and-string-stripped source, segmented by column-0 routine headers
EXCLUDING lines matching `\bforward\s*;`; "sites" = references to `Py*`
identifiers whose body is in `pyparser.inc` and not in `parser.inc`.

| | forked routines | forks | distinct `Py*` deps | sites |
| --- | --- | --- | --- | --- |
| before split 3 | 25 | 226 | 183 | 533 |
| after split 3 | 25 | 182 | 180 | 478 |

`ParseFactorCore` held 95 forks and 157 `Py*` references over 6786 lines = **29%**
of the remaining surface (not the 34% claimed). The conclusion that number was
used for — that it was by far the heaviest remaining site — survives the
correction; the figure does not.

### Two wrong-extent deletions, both caught by the compiler

Reported because the interesting part is how they were caught, not that they
happened. In the batch that removed the first 504 lines:

- the extent for the nested-def capture loop stopped **inside** the loop body,
  so `if PyExprMode ... for ... begin` went and its body stayed. It surfaced as
  `undefined variable (PyCallMeth1)` at `parser.inc:5395` — **4000 lines earlier
  than the edit**, because the unclosed routine swallowed `pyparser.inc`'s
  declarations into its own scope. A `begin`/`end`-balance check over the diff
  hunks found it.
- the `isCStringCall` if-branch was deleted as a *balanced* `if..begin..end`,
  leaving a dangling `else`. The balance check said fine; the parser said
  "statement made no progress in block". **Balance is necessary and not
  sufficient.**

Two arms are therefore not pure deletions: `tkBegin` (Pascal's behaviour is
`Error('unexpected begin in expression')`, so the guard is dropped and the NilPy
body deleted — the opposite of the mechanical reading) and the `isCStringCall`
call-result wrapper (the `else` body survives, dedented). Ten locals died with
the arms and were removed; five more were already dead at HEAD and were left,
because they are not this change's.

### Banked, NOT acted on: a candidate for split 4

**Measured and unconfirmed — re-derive before picking a target from it.** The
next-heaviest set is not another monolith but the **expression ladder**, which
is denser per line than `ParseFactorCore` was:

| routine | forks | `Py*` refs | lines |
| --- | --- | --- | --- |
| `ParseFactor` | 32 | 57 | 609 |
| `ParseExpr` | 16 | 16 | 569 |
| `ParseTerm` | 13 | 19 | 303 |
| `ParseSimpleExpr` | 10 | 22 | 271 |

Together 71 forks (39% of the remaining 182) over 1752 lines, against
`ParseFactorCore`'s 95 over 6786. Whoever takes it should note that the four are
mutually recursive and share a dispatch discipline, so they probably carve as
**one** unit, not four — and that `ParseLValueAST` (18 forks, 2512 lines) and
`ParseUsesUnitBody` (11 forks, 0 refs, 1213 lines) are the two remaining
individually-notable sites.

### Gate actually run

`make compiler/pascal26` fixedpoint converged in 1 round at every stage;
`tools/gate.sh quick` GREEN at every stage; NilPy programs run against the
CPython oracle through `tools/pydiff.py` (10 at stage 1, 16 at stage 2, 17 at
stage 3, each set chosen to hit the arms that stage touched), all MATCH. The
full matrix is Track T's, against the pushed shas. **No pin** — this is a
refactor, nothing downstream needs it blessed.

## Log
- 2026-08-20 — split 3 (ParseFactorCore) landed: `f380d7cd0`, `ec33f4e5e`,
  `3c8ec4c7d`. Figures in `f380d7cd0` superseded above.
