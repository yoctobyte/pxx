---
track: P
prio: 45
type: refactor
blocked-by: []
status: done
owner: ""
created: 2026-08-26
summary: "DONE 2026-09-05 (794fb60c5 extract, 5dbd56a3c wire). The five channel fills are now FillMatchArgChannelsAt in pasparser_call.inc, and the probe fills them and refuses on MatchArgRecMismatch — the free path's own predicate — instead of a kinds-only substitute. That closed a silent wrong value: `d.One(ia)` with an array argument and an Integer parameter printed the array's ADDRESS while the identical free call was refused. The full TypesCompatible widening was NOT done and is not unblocked by the channels: two of the four rows in the table below (a generic type parameter is tyUnknown; a routine name as a procedural value) have no channel that answers them — see the residual ticket."
---

# The overload probe cannot see the argument-match channels

- **Type:** refactor — **Track P** (`compiler/pasparser_call.inc`,
  `compiler/pasparser_lval.inc`, `compiler/symtab.inc`).
- **Filed by:** opus5-frank1, 2026-08-26, from the measurement in
  [[bug-p-a-single-candidate-method-call-does-not-check-its-argument-types]],
  which landed the narrow half and left this.

## The shape

Two argument matchers, and only one of them can see.

`MatchProcCall*` (`symtab.inc`) refuses a free call through
`MatchParamCompatible` + `MatchArgRecMismatch`. Those are not functions of the
two type kinds: they read five side channels — `MatchArgRec`, `MatchArgNil`,
`MatchArgScalar`, `MatchArgArray`, `MatchArgArrayElemTk`, each with its own
`*Valid` flag — which `pasparser_lval.inc` ≈5660-5730 fills from the parsed
`AN_ARG` chain. **Every one of those five was added because the kind pair alone
gave a wrong answer**; the comments beside them name the ticket each time.

`FindUMethOverloadAhead` (`pasparser_call.inc`) parses its arguments
SPECULATIVELY and rewinds, keeping only `argTk[]` and `argRec[]`. So it has the
kind channel and nothing else. That is survivable while it only RANKS — a wrong
rank loses a tie-break — and unsound the moment it must REFUSE.

## The measurement, which is the acceptance test

A gate built on `TypesCompatible` alone, with one candidate, refuses these
**legal** calls. Baselines: conformance 346/0, fgl 7/7.

| refused call | why the kind pair is wrong | channel that knows |
| --- | --- | --- |
| `CreateFmt('%s', [s])` | an `array of const` parameter's `TypeKind` is its ELEMENT kind | `MatchArgArray` / `MatchArgArrayElemTk` |
| `slist.Add('test', l)` | a generic type parameter is `tyUnknown` at the declaration | — |
| `SetOnKeyPtrCompare(nil)` | nil binds any reference-shaped parameter | `MatchArgNil` |
| `inherited Sort(ItemPtrCompare)` | a routine name as a procedural value types as neither | — |

Conformance went 346 → **338 pass / 8 fail** (seven of them `CreateFmt` from one
`sysutils.pas:874`) and the fgl rung went 7/7 → **0/7** on
`SetOnKeyPtrCompare(nil)` alone.

Note the trap in row 3: `MatchArgNilOk` *exists* and calling it from the probe
is the obvious move, but it gates on `MatchArgNil[]`, which only the free path
fills — so it answers False for every nil and refuses them all. **Calling the
shared predicate is not the same as reaching the shared answer.** Anything built
here has to populate the channels, not just call the function.

## The work

Lift the population out of `pasparser_lval.inc` into a helper that takes an
`AN_ARG` chain and fills the five channels, then have the probe build a chain
from the nodes it already parses and call it. Both callers then reach
`MatchParamCompatible` + `MatchArgRecMismatch` verbatim, and there is one
answer to "does this argument fit this parameter" instead of two.

Then the narrow allowlist in `FindUMethOverloadAhead` — currently "a
reference-shaped argument into a string or numeric parameter, and abstain
otherwise" — can widen to the full check and delete its own comparison.

`devdocs/dev/normalise-dont-special-case.md`, and the same shape as
`refactor-a-the-missing-layer-between-frontends-and-backends`: the duplication
is not the code, it is the *knowledge* being reconstructed in two places.

## Gate

`make compiler/pascal26`, then all four rows above compiling clean, plus:
`tools/run_pascal_conformance.sh` at 346/0, `tools/run_fgl_corpus.sh` at 7/7,
`test/test_method_arg_typecheck_ok.pas` and `..._fails.pas` unchanged, and every
`test/*.pas` compiled with only the `*_fail.pas` files refused. Those five are
what caught each class; do not believe a narrower run.

---

## 2026-09-05 (frankA) — FIVE channels confirmed; the fill range moved 750 lines

Re-derived at `3e25c7ae5`. The body says five side channels filled in
`pasparser_lval.inc ≈5660-5730`. Both halves checked:

- **Five channels, and four `*Valid` flags, not five** — `MatchArgArray` and
  `MatchArgArrayElemTk` share `MatchArgArrayValid` (`defs.inc:2861-2868`). That
  matters for the work below: whatever populates the channels from the probe has
  to know the flags are not one-per-channel.
- **All fills are in `pasparser_lval.inc`, now 6405-6509**, not 5660-5730. One
  file, nine writes, four flag-sets. The body's claim that the free path is the
  only filler holds.

**One false positive of my own worth recording, because it is the failure this
ticket is about in miniature.** My first fill census matched
`ar := MatchArgRec[j]` in `symtab.inc:9718` and reported a second filling file.
That is a READ — the channel on the RIGHT of `:=` — inside
`MatchParamCompatible`, i.e. a CONSUMER. The predicate has to name the side:

```
grep -nE 'MatchArg[A-Za-z]*\[[^]]*\] *:=' compiler/*.inc   # fills only
```

An unanchored `:=` grep counts producers and consumers as one population, which
is precisely the conflation — *"calling the shared predicate is not the same as
reaching the shared answer"* — that the body already warns about for
`MatchArgNilOk`.

### The gate's first row cannot currently answer, and it SKIPs rather than failing

Measured 2026-09-05 while establishing this ticket's baseline before touching
anything:

```
tools/run_pascal_conformance.sh
  test-pascal-conformance: SKIP — no suite at library_candidates/fpc-testsuite/tests/test
                                  (run tools/install_lib_candidates.sh fpc-testsuite)
tools/run_fgl_corpus.sh
  test-fgl: 7 pass, 0 fail, 0 skip (of 7) — PASS
```

The Gate section says *"conformance 346/0 ... Those five are what caught each
class; do not believe a narrower run."* **On this checkout the conformance row
is not a narrower run, it is no run**, and it exits 0 saying so. The fgl
baseline is live and is 7/7.

That matters more than usual here because the body's measurement table credits
conformance with **seven of the eight** regressions the naive gate caused — all
`CreateFmt` from one `sysutils.pas:874`. So the row carrying most of this
ticket's evidence is the row that currently cannot speak, and a SKIP reads as a
pass to anyone grepping for a failure. **Install the suite first**
(`tools/install_lib_candidates.sh fpc-testsuite`) **and confirm it prints 346
before trusting a green here** — a baseline of "SKIP" would let the whole
widening land unmeasured.

---

## 2026-09-05 (frankA, later) — the suite is INSTALLED and the Gate's baseline number is stale: it is 347/2, not 346/0

The note above said the conformance row could not answer. It can now —
`tools/install_lib_candidates.sh fpc-testsuite` was run (it writes only into the
gitignored `library_candidates/`, needs no authority, and says so itself:
*"nothing entered the repo"*).

**Measured baseline at `abe92579b`, before touching anything:**

```
test-pascal-conformance: 347 pass, 2 fail, 167 skip, 34 auto-gated (of 550)
  FAILURES: tgenfunc17.pp(accepted-invalid) tgenfunc18.pp(accepted-invalid)
tools/run_fgl_corpus.sh: 7 pass, 0 fail, 0 skip (of 7) — PASS
```

**The Gate section's `conformance 346/0` is wrong today, and wrong in the
direction that would have cost a session.** Anyone taking this ticket, running
the suite for the first time and seeing 347/2 would read two failures as damage
they had just done. They are neither theirs nor new.

### The two failures are unrelated to argument matching, and their old pass was accidental

Filed as
[[bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface]].
Both are `{ %FAIL }` rows about a `generic procedure` declared `<T>` and
implemented `<S>`. **The pinned compiler rejects them because it cannot parse
`generic procedure` at all** — it never looks at the type parameters — and a
`%FAIL` row scores any refusal as a pass. `71deb21d4` added the syntax and the
rows went red the moment the compiler could read the files.

That matters here beyond bookkeeping: **`tstate/conformance.tsv` records both as
`pass` as of 2026-09-02**, so the archive a later session would consult to
establish "what was green before" carries the accidental pass too.

### The working baseline for this ticket

- conformance **347/2**, and the two FAILs are stable, named, and must not be
  counted against a widening here;
- fgl **7/7**, live;
- so the acceptance test in the body still stands as written — a naive
  kinds-only gate must not move either number, and the four refused calls in the
  table are still the four classes to satisfy.

**Assert the suite is present before reading any conformance result**: with
`library_candidates/fpc-testsuite` absent the harness prints SKIP and **exits
0**, so a green is indistinguishable from no run. That is the same shape as the
`%FAIL`-passes-on-refusal above — two ways this one harness returns a pass for
something that never happened.

---

## 2026-09-05 (frankA) — step 1 of 2: the channels are extracted, and the helper is PER-ARGUMENT rather than per-chain

The body proposes *"a helper that takes an `AN_ARG` chain and fills the five
channels, then have the probe build a chain from the nodes it already parses."*
**Built per-ARGUMENT instead, and the reason is about the probe rather than
about tidiness.**

Reading the five fills before moving them: **every one is a pure function of
`(node, argTypes[i])`.** None reads a neighbour, none reads the chain, none
needs `nArgs`. The chain walking was incidental — five separate
`for i := 0 to nArgs-1` walks of the same list, one per channel.

So a chain-shaped helper would force `FindUMethOverloadAhead` to BUILD a chain
from nodes it has already parsed — and **that probe rewinds its token stream**.
`TokPos := savedCurIdx` puts the tokens back; it does not put back `AN_ARG`
nodes allocated into the arena. A per-argument entry point lets the probe call
the filler exactly where it already holds `CurASTNode` and allocate nothing.

`FillMatchArgChannelsAt(i, node: Integer; argTk: TTypeKind)` lives in
`pasparser_call.inc`, which is included BEFORE `pasparser_lval.inc`, so it is
visible to the probe (same file) and to the free path (later file). The four
`*Valid` flags stay with the caller, which is where the "single entry into
`MatchProcCall*`, so the channels stay fresh across the retry matches" contract
lives — that contract is the caller's, not the filler's.

`MatchCallDelphiProcAddr` goes from 118 lines of fill to 22.

### What was verified, and what each check cannot see

1. **Static identity of all five channel expressions.** Comments stripped,
   `argTypes[i]`/`argTk` and `ASTLeft[currArg]`/`node` normalised to one
   spelling, then each `MatchArgX[i] := ...;` compared. All five identical.
   Controlled twice: the greps are non-empty (152/42/832/316/93 chars — two
   EMPTY greps also compare equal, which is the vacuous pass this check
   invites), and perturbing one operand in a copy reports CHANGED.
2. **Byte-identity of what the compiler EMITS**, old binary vs new, over the test/ corpus.
   This is the check that matters, because static identity of the moved text
   says nothing about the loop that now drives it.
3. `make compiler/pascal26` converged; conformance and fgl against the TRUE
   baseline recorded above (347/2 and 7/7, not the 346/0 in the Gate section).

**What none of them can see** is a channel the free path never fills in this
corpus — byte-identity scopes to the producers the corpus reaches. The four rows
in the body's table are the acceptance test for that, and they belong to step 2.

### Step 2, deliberately NOT taken in the same change

Having the probe call the filler is the capability change, and it has a hazard
worth naming first: **the channels are GLOBALS.** The contract in
`MatchCallDelphiProcAddr` is "fill at the single entry, then match, then
retry-match against the same argument list". The probe runs during ARGUMENT
PARSING, i.e. before that entry is reached with a parsed chain — which is why it
looks safe — but "looks safe" is the wrong standard for a globals-lifetime
question. Establish that no free-path fill can be live across a probe before
wiring it, then gate on the four rows in the body's table plus both baselines.

---

## 2026-09-05 (frankA) — the globals-lifetime question step 1 deferred, ANSWERED; and the gap has a repro

Step 1's note ended: *"Establish that no free-path fill can be live across a
probe before wiring it."* Established, and the answer has two halves — one that
clears step 2, one that was a defect in its own right and is now fixed.

### Half 1 — the free path cannot have a live fill across a probe

`MatchCallDelphiProcAddr` fills at `pasparser_lval.inc:6489`, then matches and
retry-matches down to its end at 6679. Comments and string literals stripped
programmatically, that whole 191-line window contains **no** `Parse*`, `Next`,
`Expect`, `Eat`, `Rewind*` or recursive `FindUMethOverloadAhead`. Nothing in it
can parse, so no nested probe can run inside it, so the free path's fill is
never live across one. **The direction that looked dangerous is closed.**

The direction that actually *is* dangerous runs the other way, and it is the
probe against ITSELF: `a.M(b.N(x), y)` runs a second probe inside the first
one's argument-parsing loop. A fill placed in that loop would let the inner
probe overwrite the outer one's channels before the outer one read them. So the
fill must go **after the rewind** — measured the same way, lines 2500→end of
`FindUMethOverloadAhead` contain zero parse-capable calls — which is why the
parsed nodes are now carried in a local `argNode[]` rather than read off
`CurASTNode` in the loop.

### Half 2 — the `*Valid` flags were never a per-call lifetime, and one reader was already exposed

The four flags are set `True` in **exactly one place in the tree** and set
`False` in **none**. So after the first filled call they are True for the rest
of the process, with the previous call's answers still in the arrays. The
`defs.inc` contract said *"paths that never fill the array are safe"*; that held
only before the first filled call.

`PyParseVariadicMinMax` (`pyparser.inc`) is the one caller of `MatchProcCall*`
that does not fill, and instrumenting the read site showed it reading:
`test_nilpy_min_max_variadic.npy`, **ten reads, all four flags True**, with
`MatchArgScalar[0]` and `[1]` carrying a leftover True. Fixed in `bc2fe10f1`,
which declares them invalid there and corrects the contract comment. **No
answer-changing case was constructed** and the fix does not claim one: that
fold's candidates are the 2-argument min/max overloads, whose parameters are
plain scalars, so no channel has an array, record or class parameter to
disqualify. Candidate-set luck, not a property of the code.

### The gap this ticket is about now has a repro, and it is SILENT

```pascal
type TIA = array[0..2] of Integer;
     TD = class procedure One(v: Integer); end;   { ONE candidate }
var d: TD; ia: TIA;
begin d := TD.Create; ia[0] := 11; d.One(ia); end.
```

| | |
| --- | --- |
| pxx, method spelling | compiles, prints `one 4306992` — the array's ADDRESS |
| pxx, free `One(ia)` | **refused**, "candidates: One(Integer)" |
| fpc 3.2.2 | refused, *Incompatible type for arg no. 1: Got "TIA", expected "LongInt"* |
| pin v403 | prints `one 4306992` — **pre-existing, not a regression** |

That is `bug-p-an-array-argument-binds-a-scalar-overload` — fixed for the free
path by adding `MatchArgArray` — arriving through the method path, which could
not see the channel. The two spellings of one call disagree, and the method one
is the silent one. It is the ticket's thesis with a number attached.

### Step 2 as landed, and what it deliberately does NOT do

The `nCand = 1` gate now fills the channels and calls `MatchArgRecMismatch` —
the free path's own predicate — instead of only its narrow allowlist. Indexed
by the **parameter** slot `pj`, not the argument slot `j`: `Params[0]` is Self
on every method, and `MatchArgRecMismatch` reads `Params[j]` and `MatchArg*[j]`
with one `j`. Under NilPy keywords `OverloadArgParamIdx` makes that mapping
non-identity, which is the second reason not to assume `j`.

**The narrow allowlist stays.** The body's table lists four legal calls a
kinds-only gate refuses, and two of them — `slist.Add('test', l)` (a generic
type parameter is `tyUnknown` at the declaration) and `inherited
Sort(ItemPtrCompare)` (a routine name as a procedural value) — have a dash in
the "channel that knows" column. Filling all five channels does not answer
either, so widening the `TypesCompatible` half would still refuse them. Reaching
the shared *refusal* predicate is what the channels buy; the full compatibility
check is not unblocked by this step and should not be attempted as if it were.

The flags are cleared again on the way out, for the reason half 2 gives.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
