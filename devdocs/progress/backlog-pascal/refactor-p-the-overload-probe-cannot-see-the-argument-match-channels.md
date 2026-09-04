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
