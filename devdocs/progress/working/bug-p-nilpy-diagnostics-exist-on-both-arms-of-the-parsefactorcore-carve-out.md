---
track: P
prio: 55
type: bug
status: working
blocked-by: []
owner: frankD
summary: "MEASURED 2026-09-04 and the ticket below is wrong in both halves. The count is not ten: it was 30 of 36 at this ticket's own commit and is 28 of 30 at HEAD -- the 10 was a `comm` artefact under the default locale, reproducible exactly and only there. And the prescribed fix is backwards: a reachability probe over all 830 .npy programs says ALL 28 Pascal-arm sites inside ParseFactorCore are UNREACHED (17 of them provably, behind the PyExprMode dispatch) while all 3 outside it are live. So the body tells its taker to preserve and share ~28 arms that should be DELETED, which is a wrong-change-lands risk rather than a mis-scheduled tidy-up, and is why this is no longer a 35. Do NOT use duplication as the test: a duplicated diagnostic (TPyList.extend) is live. Position relative to the dispatch is the only discriminator. The measured population now also lives in the pasparser_expr.inc comment above the dispatch, so it survives this ticket."
---

# Ten NilPy diagnostics exist on both arms of the ParseFactorCore carve-out

- **Type:** bug (maintenance hazard, not a wrong answer today) — **Track P**
  file-ownership (`compiler/pasparser_expr.inc`), touching **Track N**
  (`compiler/pyparser.inc`). One agent holding P+N can do both; otherwise it is
  a P change plus an N change.
- **Found:** 2026-08-29, by the coordinator, while correcting a stale quoted
  diagnostic in `devdocs/dev/nilpy-semantics-divergences.md` for frankD.

## What is actually there

The carve-out is deliberate and documented — `compiler/pyforwards.inc:37`:

> `procedure PyParseFactorCore; forward;  { the NilPy half of ParseFactorCore, carved out into pyparser.inc — ParseFactorCore dispatches here on PyExprMode }`

**It is partial.** Measured at `d6cd7ebb9`:

| | `Nil Python:` diagnostics |
| --- | --- |
| `compiler/pyparser.inc` | 505 occurrences, 312 distinct |
| `compiler/pasparser_expr.inc` | 37 occurrences, 36 distinct |
| **present verbatim in BOTH** | **10** |

The ten:

```
Nil Python: exec(src) with no namespace is not supported — …
Nil Python: expected method after super().
Nil Python: getattr on an attribute this type does not declare needs a default
Nil Python: len() could not call __len__
Nil Python: promocore (PXXPromoToBase) not loaded
Nil Python: promocore (PXXPromoToStr) not loaded
Nil Python: pyeval (EvalPyStmts) not loaded
Nil Python: pyeval (pyeval_expr) not loaded
Nil Python: pyfilter_iter_i / pymap_iter_i not loaded
```

The `exec` one is byte-identical across `pyparser.inc:44129` and
`pasparser_expr.inc:2615` — the same six-line `Error('…')` construction,
including the doubled quote in `caller''s`.

## Why it is worth a ticket rather than a shrug

This is the shape `devdocs/dev/normalise-dont-special-case.md` names — *if you
fix a bug on one arm of a double case, grep for the sibling before closing the
ticket* — and the double arm here is **invisible from either side**. Someone
improving the `exec` refusal reads one file, sees one definition, and has no
signal that a second copy exists. The failure mode is not a wrong answer, it is
a correction that lands at 50% and reports success.

It has a live consumer: `docs/targets/nil-python.md` (frankD, `ca3815d74`)
QUOTES the exec refusal on the public website, and
`devdocs/dev/nilpy-semantics-divergences.md` quotes it too. A future edit to
whichever arm the author happens to open can leave the published page quoting
the other. The doc quote had *already* rotted once — it was missing the whole
final clause until `d6cd7ebb9` — and that was against a single arm.

## What is NOT claimed here

- **Not** that the carve-out was wrong. Duplicating a parser *across* languages
  is the deliberate rule
  (`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`): share the AST
  and the IR, duplicate the parser. This ticket is about the ten places where
  the duplication is *within* the split rather than across it.
- **Not** that either arm is dead. Nobody has measured which arm a `.npy`
  compile actually reaches for these ten, and reasoning about the `PyExprMode`
  dispatch is not measurement. **Do that first** — the answer changes the fix.
- **Not** that all 36 residual strings should move. Several are `… not loaded`
  runtime-library guards, which may legitimately belong on both arms.

## Work

1. **Measure, do not reason.** For each of the ten, determine which arm a
   NilPy compile reaches — `PXXDBG` or a deliberate divergence in one copy's
   text, then compile a `.npy` that triggers it and read which text appears.
2. Dead arm → delete it. Live on both → hoist the string to one shared
   constant so the two arms cannot drift, which is the normalise-don't-
   special-case answer and is cheaper than keeping them in sync by discipline.
3. Leave the `… not loaded` guards alone unless step 1 says otherwise.

Gate is the owning lane's ordinary one; per CLAUDE.md that is
`make compiler/pascal26` plus the repro, and breadth is Track T's.

---

## 2026-09-04 (frankA) — the count was wrong by 3x, and it was the LOCALE

**The ticket says ten. It was thirty.** And the correction is not tree drift —
I recovered the ticket's own commit and ran both instruments on it.

`d6cd7ebb9` is not on origin. Per CLAUDE.md the ghost rate is ~100% by
construction, and the documented recovery is to match the SUBJECT — frankH
pointed me at it after I had already written the citation off as dead, which
was my error. `git log origin/master -S "exec(src) with no namespace"` finds
**`e60d03351`**, *"the quoted ambient-exec refusal was missing its last
clause"* — verbatim the correction this ticket says it was made during.
`30a44d559` is the ticket-filing commit.

| tree | `LC_ALL=C` | default (`en_US.UTF-8`) | `grep -F` per string, no sort, no `comm` |
| --- | --- | --- | --- |
| `e60d03351` | **30** | **10** | 30 of 36 |
| `30a44d559` | **30** | **10** | 30 of 36 |
| HEAD | **28** | 9 | 28 of 30 |

**The 10 reproduces exactly, and only under the default locale.** Tree drift
contributed nothing at the time; the residual has since shrunk from 36 to 30 by
other work, which is why HEAD reads 28 of 30.

### The instrument

`sort` under `en_US.UTF-8` collates by a rule `comm` does not assume. `comm`
prints `comm: file 1 is not in sorted order` **to stderr** and a **partial
answer to stdout** — it does not exit nonzero and the partial answer has
exactly the shape of a real one. So the number got written down.

**The tell was in the artefact, not the tooling**: the list in the body under
the heading *"The ten"* has **nine** entries. Anyone re-reading the ticket
could have caught it; no amount of better tooling would have.

### What that does to the ticket's framing

The body describes *"the ten places where the duplication is within the split
rather than across it"* — a small residue to tidy. The measurement says
**essentially the entire residual set is duplicated**: 30 of 36 then, 28 of 30
now, with exactly **two** strings unique to the Pascal arm. That is not a
tidying job. Nobody would have ranked it 35 knowing it.

## Step 1 performed: which arm does a NilPy compile reach

The body says *"Measure, do not reason ... reasoning about the `PyExprMode`
dispatch is not measurement"*, and it is right, because reasoning gets this
wrong in a specific way described below.

### The probe had to be built the hard way, and here is why

Every one of these is a `... not loaded` RTL guard. A probe that fires **when
the guard fires** can only speak when the RTL is broken — it would have printed
nothing and I would have called that a negative. So the probe wraps the
**condition**, not the body:

```pascal
if PasArmReached(<cond>, <site id>) then Error('Nil Python: ...');
```

`PasArmReached` logs the site id to stderr and returns its argument. It fires on
**reaching** the site regardless of the guard, it is a pure expression
substitution so it is safe inside any `if`/`else` chain, and it is **labelled
per site** — a shared id could not attribute a fire.

**Then it had to earn its zero.** Two must-fire controls were installed at the
`PyExprMode` dispatch itself: id 999 on the Pascal arm, id 998 on the NilPy arm.
Pascal source: **4439** fires of 999, zero of 998. NilPy source: **44471** of
999 and **115** of 998. Only after that was a zero from the 27 real sites
allowed to mean anything.

27 of the 31 sites are `if COND then Error(...)` and carry the probe. The other
4 are **bare** `Error(...)` — reaching one IS erroring, so they self-report; the
census log contains zero `Nil Python:` errors, so they did not fire either.

### The result, at the full denominator

**830 of 830 `.npy` programs compiled, zero compile errors.** Control fires:
96,795. Site fires:

| | sites | fires |
| --- | --- | --- |
| **inside `ParseFactorCore`** (24 probed + 4 bare) | 28 | **0** |
| **outside it** (`PyMakeUnsupportedOperand`, `ParseExpr` x2) | 3 | **3** |

**Position relative to the `PyExprMode` dispatch at `:561` is a perfect
discriminator — 0 of 28 against 3 of 3 — and it is the only thing that is.**

**17 of the 28 are dead STRUCTURALLY**, not merely unobserved. They gate on
`NilPyUserCode`, and `symtab.inc:25` defines it as `isNilPy and ((CurrentUnitIdx
< 0) or PyExprMode)`. Below the dispatch `PyExprMode` is false by construction,
so the guard reduces to `isNilPy and CurrentUnitIdx < 0` — the **main program of
a NilPy compile parsed as non-Python**, which a `.npy` cannot produce, since its
main program is Python and therefore left at the `Exit`. The other 11 gate on
plain `isNilPy`, which **is** true while the Pascal RTL is parsed, so they are
reachable in principle and their zero is empirical only. **Two claims of
different strength; the first must not carry the second.**

The 4 bare sites are a **measured zero with a denominator**, not an absence: 830
clean compiles produced no `Nil Python:` line at all, which is a fact about what
the corpus covers as much as about the sites.

### The zero is not vacuous — the denominator check

Programs in the corpus containing each construct these arms serve: `int(` 820,
`len(` 246, `open(` 25, `map(` 23, `float(` 22, `round(` 17, `getattr` 12,
`sys.` 11, `filter(` 11, `exec(` 9, `divmod` 6, `next(` 5. **Every construct,
richly represented, and not one reached the Pascal copy.**

That table was wrong the first time I built it and is worth recording, because
the next census will be built the same way. With `grep -E` the pattern `len(`
opens an unterminated group, and it reported **0 of 830 for nearly everything** —
which would have made the whole negative read as vacuous. `grep -F` gives the
numbers above.

**The failure was loud and I could not hear it**, which is the part to copy.
Measured directly:

```
grep -lE 'len(' <files>   ->  rc=2
                              stdout: empty
                              stderr: error at position 8 ... mismatched (
```

The tool announced itself correctly, on **stderr**, with a **nonzero exit** —
and the count was built as `n=$(grep -lE ... | wc -l)`, so the pipe consumed the
empty stdout, `wc` honestly reported 0, and the command substitution threw the
exit code away. Every stage behaved correctly and the number was about nothing.
This is `&&`-between-stages, not `;`, in its most ordinary clothes: **a
denominator check whose own precondition was never branched on.** A census that
prints a denominator to prove a zero is not vacuous can have a vacuous
denominator, and it will not look different.

### A claim I made mid-run and am withdrawing

At 291 of 830 I reported that duplication and deadness **coincided exactly** —
the only two sites firing were the only two strings not duplicated on the NilPy
arm — and I said so to a peer as the most trustworthy part of the result,
because the two axes were derived independently and the probe never saw the
string sets.

**It dissolved at the full denominator.** The third site to fire, `TPyList.extend`
(`ParseExpr`), **is** duplicated. So:

> **Duplication does not predict deadness. Position does.**

Anyone deleting Pascal-arm copies on the "it exists on both arms" test would
have removed a live one. The corrected discriminator is stricter *and* simpler,
so the finding survived being wrong — but the pattern was clean, mechanistically
plausible and false, at 35% of the corpus.

### What to actually do, which is not what the body says

The body's step 2 (*live on both -> hoist to a shared constant*) and step 3
(*leave the `... not loaded` guards alone unless step 1 says otherwise*) are both
retired by step 1. Nearly all of these **are** the `not loaded` guards and they
are **dead**, so the answer is **delete**, not **share**.

**Scope honestly**: the diagnostics are dead because their enclosing BRANCHES
are dead. Deleting the `Error` lines alone would leave unguarded dead branches,
which is worse than leaving them. The work is removing ~28 dead arms from an
8002-line function, incrementally, and that is a real change rather than a tidy —
which is the other half of the re-rank.

This is the same fix as
[[bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag]],
which removed nine such arms from this very function on the same reasoning. Its
comment (`pasparser_expr.inc`, above the dispatch) says *"if you are about to add
an `isNilPy` arm here: it cannot fire."* **It was written about nine arms and is
true of 28 more that nobody re-swept.** That comment now carries this
measurement, so the population is stated where the next person greps rather than
only here.

### Not done, and why

The measurement is banked; the deletion is not attempted. ~28 arms in a hot file
that Track A, P and the C frontend all read, landed one at a time each green, is
past what is left of this session — `root-cause-over-microfix.md`'s "bank the
diagnosis and park it" rather than a consolation microfix.

---

# 2026-09-06, frankD: the reachability zero re-measured at HEAD, with the control in the same build

Re-ran the 2026-09-04 sweep at `62448f1b0` because a verification claim scopes to
the tree it was taken on, and `5f177b181` (soft keywords) had landed since.

**One instrument carrying both the control and the measurement**, so a zero
cannot be a dead probe. Two lines, one build, either side of the dispatch at
`pasparser_expr.inc:605`:

```pascal
  if NilPyUserCode then WriteLn('PROBE-ABOVE');
  if PyExprMode then begin PyParseFactorCore; Exit; end;
  if NilPyUserCode then WriteLn('PROBE-BELOW');
```

Over every `.npy` program in `test/`:

```
programs=827   above_total=96762   below_total=0
```

`NilPyUserCode` is true **96,762 times** above the dispatch and **never once**
below it. A separate control build would have left exactly the gap that matters
open; here the same binary proves the predicate can be true and the probe can
print.

## Why this is a proof and not only a census

`NilPyUserCode` is `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`
(`symtab.inc:25`). The dispatch Exits whenever `PyExprMode`, so below it the
predicate reduces to `isNilPy and (CurrentUnitIdx < 0)` — a NilPy compile whose
MAIN PROGRAM is being parsed as Pascal. `isNilPy` is set from the root file's
extension alone (`compiler.pas:1970`, `.npy`/`.py`), so a `.npy` cannot produce
it. The corpus agrees with the argument rather than substituting for it.

## The arms, counted as arms

The `17 / 11` above counts diagnostic SITES. What a deletion removes is ARMS,
and there are **14 guarded by `NilPyUserCode`** — every one a top-level
`if`/`else if` with the predicate as its leading conjunct, read individually
rather than inferred:

`__file__` 1974 · `len` 2114 · 2276 · `int` 2339 · `exec` 2733 · `eval` 2780 ·
`open` 2876 · `float` 2960 · `map` 3009 · `filter` 3086 · `next` 3123 ·
`str` 3209 · `round` 3387 · `divmod` 6411

...and **4 guarded by plain `isNilPy`** (2473, 3372, 3442, 3492), which is TRUE
while the Pascal RTL is parsed. Those stay: their zero is empirical only, and
deleting code you believe is dead is still wrong.

A first pass at this classification used nearest-preceding-guard within 400
lines and disagreed with the recorded count. It turned out to be right, but only
reading all eighteen guard lines established that — **a heuristic that happens to
agree is not an instrument**, and the deletion must not rest on one.

## Still to do

Delete the 14, one at a time with a build between each (they sit in an `else if`
chain; two — 3387 and 6411 — are nested rather than standalone and need reading
individually). `tools/npy_differential.sh` shape: capture compile+run output for
all 827 before and after and require byte-identity, **with a positive control
that deletes a LIVE arm and must differ** — "output identical" is also what
deleting nothing produces.
