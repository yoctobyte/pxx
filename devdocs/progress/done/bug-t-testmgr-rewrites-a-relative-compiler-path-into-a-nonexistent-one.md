---
slug: bug-t-testmgr-rewrites-a-relative-compiler-path-into-a-nonexistent-one
track: T
prio: 55
type: bug
status: done
owner: frankB
created: 2026-09-09
found-by: frank-seven
tags: [testmgr, harness, snapshot, false-red]
blocked-by: []
summary: "FIXED 2026-09-09: COMPILER_PATH_RE was unanchored on the left, so `../../compiler/pascal26` -- which CONTAINS `./compiler/pascal26` at offset 4 -- kept its leading `..` through the rewrite onto the per-run snapshot and became a path that does not exist. Silent in both directions: the row's leading `!` made the missing binary EXIT 0 and PASS, and the next row's bare `grep -q` printed nothing when it failed, so test_libmanifest was RED under testmgr, GREEN under gate.sh quick and bare make, with a 0-byte log. Now consumes the whole relative prefix. THE pin_built WARNING IN THIS TICKET WAS BACKWARDS and is corrected below: the old pattern already matched those rows -- that is why it mangled them -- so bool(search) cannot move. Measured over 42 tier targets / 5987 recipe lines: 1 substitution moves, 0 bool(search), 0 lost. `tools/testmgr.py --tier native --job test-core#src:test/test_libmanifest.pas` is GREEN. Guard: tools/testmgr_compiler_path_devtest.py."
---

# The mangling, measured

```
IN : cd test/libmanifest && ! ../../compiler/pascal26 unitalias_no_row.pas out
OUT: cd test/libmanifest && ! .././tmp/testmgr-abc123/compiler/pascal26 ...
```

`RUN_COMPILER` is absolute (`os.path.join(RUN_TMP, "compiler", "pascal26")`), so
the surviving `..` prefix turns an absolute replacement into a relative path that
resolves, from `test/libmanifest`, to `test/tmp/...`. Nothing is there.

# The fix, and the one thing to check before landing it

Consume the whole relative prefix rather than a suffix of it:

```python
COMPILER_PATH_RE = re.compile(r"(?<![\w.-])(?:\.{1,2}/)+compiler/pascal26(?![-\w])")
```

`./compiler/pascal26` matches with one repetition, `../../compiler/pascal26` with
two, and the left-hand guard stops it matching inside a longer path. Because
`RUN_COMPILER` is absolute, substituting the entire prefix is correct from any
CWD, which is what makes this a one-line fix rather than a CWD calculation.

**But the same constant is load-bearing elsewhere and this widens it.**
`testmgr.py:2155` uses `not COMPILER_PATH_RE.search(body)` to decide
`Job.pin_built`. Today a `../../compiler/pascal26` row does NOT match, so it is
classified as pinned; after the fix it matches and is classified HEAD-built.
That is almost certainly the correct classification — the row does invoke the
HEAD compiler — but it is a behaviour change to a field the pin path reads, and
it must be stated in the commit rather than discovered later. Check whether any
`pin_built` count moves, and say so either way.

Do not "fix" this by respelling the libmanifest rows as `./$(COMPILER)`. The
`cd` is the point of that test — it exists to compile a unit from inside its own
directory — and rewriting the test to suit the harness is the compiler-appeasement
shape applied to tooling.

# Why it was invisible

Green under `gate.sh quick`, green under bare `make`, red only under testmgr, and
the red carries an empty failure-detail block. So the one instrument that sees it
is the one that cannot say what it saw. See the sibling ticket
`bug-t-a-failing-grep-q-step-leaves-the-archive-unable-to-say-what-broke`.

# Provenance

frank-seven, on seven at `2d3e5fb9dfd6`, running the mangled command verbatim to
confirm the exit-0 behaviour. Reached only after establishing that frankZ's
paired test passes by hand in both arms — control silent, bare-filename arm
fires the note, exactly one of two, which is the property the pair asserts.

## 2026-09-09 (frankB) — FIXED, and the `pin_built` warning in this ticket was backwards

`COMPILER_PATH_RE` now consumes the whole relative prefix:

```python
COMPILER_PATH_RE = re.compile(r"(?<![\w.-])(?:\.{1,2}/)+compiler/pascal26(?![-\w])")
```

The libmanifest row rewrites to the absolute snapshot path from any CWD, which
is what makes this a pattern change rather than a CWD calculation. The row is
untouched — the `cd` is the point of that test.

**THE `pin_built` CONCERN CANNOT MATERIALISE, and it is worth writing down why
rather than just reporting a zero.** This ticket predicted that a
`../../compiler/pascal26` row *"does NOT match today"* and would start to,
reclassifying it from pinned to HEAD-built. It **does** match today — matching
a suffix of the prefix is *precisely* why it mangles the path — so
`bool(search)` was already True and `not COMPILER_PATH_RE.search(body)` is
unchanged. The prediction and the defect are the same fact read two ways.

**Measured, not reasoned**, over every target in every tier:

```
42 targets, 5987 recipe lines naming compiler/pascal26
  substitution RESULT moves .................. 1   (the libmanifest row)
  bool(search) moves -> pin_built could flip .. 0
  substitution LOST (old matched, new does not) 0
```

My first census answered a different question and said `0` for all three — it
filtered on *"newly matches"*, which is this ticket's premise, so it inherited
the premise and could not see the one row that does move. **A census built on
the hypothesis it is testing agrees with it.** The corrected one compares
`OLD.sub(...)` against `NEW.sub(...)` per line, which is the property that
actually matters.

## Guard

`tools/testmgr_compiler_path_devtest.py`. Six rows, and three of them are the
point:

- a **positive control** that asserts the OLD pattern still produces `../.` +
  the snapshot path. Without it the file asserts that the new pattern works and
  says nothing about whether the bug was real.
- the **`bool(search)` invariant** across all seven spellings, so `pin_built`
  cannot start moving silently later. This is the row that would have caught
  the wrong premise.
- an **aim check** on the Makefile: `cd test/libmanifest && ! ../../$(COMPILER)`
  must still be spelled that way. Every other row tests a string literal, so if
  the recipe were respelled to dodge the regex — which this ticket forbids —
  they would all pass while guarding nothing.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6aa50d6eb.

## CORRECTION 2026-09-09 (frankB) — two claims in `6aa50d6eb` were false when pushed

**1. "Verified: tools-devtest 161 guard(s) green, a complete run" was not true of
the tree it shipped on.** The sweep was green against the tree it ran on; 79
commits were pulled during that session, and one of them had respelled the
libmanifest row. The number was quoted afterwards as if it described the pushed
tree.

**This is a THIRD shape of the measure-then-move hazard and the existing rule
covers it, but not obviously.** CLAUDE.md's sequence (push, let the pull settle,
**rebuild**, measure) is written about a measurement going stale because the
tree moved *under* it, and its mirror is a pull *improving* a number you did not
earn. This one is neither: the measurement was correct when taken and the tree
moved in the gap between taking it and pushing it, so **the number got
better-looking by being older** — and nothing in the commit looked wrong,
because a stale green is indistinguishable from a fresh one. Re-run the cheap
guards after the rebase, not before it.

**2. The aim check it added was BORN RED and could never have passed.**
`t_the_real_recipe_row_still_exists_and_still_spells_it_that_way` asserted the
literal `cd test/libmanifest && ! ../../$(COMPILER)`, which appears **0 times at
`6aa50d6eb^`** — its own parent. The row had already been respelled to resolve
the binary with `readlink -f` before the `cd` (`17a0e4bd6`, an ancestor), which
is a better fix and the opposite of a dodge: an absolute path cannot be mangled
by a prefix rewrite at all.

**The assertion was written from this TICKET's description of the row, not from
the tree.** That is the same failure as the census this ticket already records —
a ticket you have just read is the most available description of the code and it
is not the code — and it produced a guard that manufactured a regression rather
than detecting one, reading as a failure of whatever landed beside it. Rewritten
to assert the PROPERTY (some recipe still invokes the compiler from inside
`test/libmanifest` with a `!` refusal) rather than a spelling, and the
`LIBMANIFEST` fixture's "the real row ... not a paraphrase" comment corrected in
the same pass — a fixture that claims to be live is what invited the stale
assert.

Found by frank-seven running the loop on seven (160 green, 1 red) and relayed by
frankuser; both halves re-derived here before acting.
