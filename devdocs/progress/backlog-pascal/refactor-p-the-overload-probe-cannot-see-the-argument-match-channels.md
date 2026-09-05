---
track: P
prio: 45
type: refactor
blocked-by: []
status: backlog
owner: ""
created: 2026-08-26
summary: "The speculative overload probe in FindUMethOverloadAhead has only argument KINDS, while the free-call path has five side channels (MatchArgArray/ArrayElemTk/Nil/Rec/Scalar) filled in pasparser_lval.inc. So the probe cannot run the free path's own compatibility check — measured, a gate built on kinds alone refuses four classes of legal call. Lift the population into a helper both callers share."
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
