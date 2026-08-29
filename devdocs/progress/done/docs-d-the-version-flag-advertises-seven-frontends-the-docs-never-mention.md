---
track: D
prio: 20
type: docs
blocked-by: []
summary: "`pxx --version` prints twelve frontends — pascal c nilpy rust zig ada basic fortran algol erlang lolcode whitespace — and `docs/**` mentions five. A reader who runs the flag sees Ada, Fortran, Algol, Erlang, BASIC, LOLCODE and whitespace nowhere in the documentation, with no way to tell a demo target from an esoteric probe. Decide what the public docs say about the other seven."
status: done
owner: frankD
---

# `--version` advertises seven frontends the docs never mention

- **Track D** — prose only.
- **Raised by** frankD while documenting the information flags
  ([[docs-toolchain-cli-flags]]), which had to reprint the line. That page carries a
  one-sentence disclaimer as a stopgap; this ticket is the real answer.

## The gap

`pxx --version` (pinned v391):

```
frontends:   pascal c nilpy rust zig ada basic fortran algol erlang lolcode whitespace
```

`grep -rn "Fortran\|Algol\|LOLCODE\|Erlang" docs/` returns **nothing**. The docs
cover Pascal, [C](../targets/c-frontend.md), Nil Python, and Rust/Zig as
experimental. Seven names in that line appear in no public page.

They are not vapour — each was fed a source file with its own extension and answered
with a *frontend-specific* diagnostic (`Fortran: unexpected statement`, `Erlang: no
main/0 found`, Algol's own parser error), so the lexers and parsers really run. But
the reader has no way to tell what any of them is for, and the list flattens two very
different things:

| | its own ticket calls it |
| --- | --- |
| `basic` | *"PXX Basic — own free-form BASIC dialect (real demo target, not an esoteric probe)"* |
| `fortran`, `algol`, `lolcode` | *"Esoteric probe: …"* |
| `ada`, `erlang`, `whitespace` | not checked when this was filed |

## Why it is worth deciding rather than ignoring

The string is **hand-maintained** — `compiler/compiler.pas:272`, a literal, not a
registry read — so it is already a drift risk, and it is the most public surface the
esoteric frontends have. Left as is, `--version` is the only place a user learns
these exist, and it reads as a support claim for Ada and Fortran.

## Options

1. **A short "other frontends" page** under `docs/targets/`, saying plainly which are
   demo targets and which are probes, and that neither carries a compatibility
   promise. Cheapest honest fix; the tickets already contain the material.
2. **One paragraph in `docs/targets/index.md`**, no new page. Less discoverable, but
   the list is short.
3. **Leave the docs alone and change what `--version` prints** — group the line, e.g.
   `frontends: pascal c nilpy (rust zig experimental; +7 probes)`. That is Track A's
   file, so it would be filed there; recorded here because it is the alternative that
   actually removes the gap rather than documenting around it.

**Recommendation: option 1**, and it is small — a page that exists mostly to say
"these are probes, do not build on them" is worth more than the silence, which
currently reads as an omission rather than a decision. Option 3 is a good companion
but not a substitute: the names stay reachable either way.

## Not in scope

Whether any probe should be *promoted*, and anything about the frontends' behaviour.
This is about what the public docs say exists.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Option 1 as recommended and as the coordinator confirmed: a short
`docs/targets/other-frontends.md` (order 66), linked from `docs/targets/index.md`
and from the `--version` paragraph in `docs/reference/cli.md`. Option 3 —
changing what `--version` prints — was **not** pursued: that is
`compiler/compiler.pas:272`, Track A's file.

### What the page says

A four-row table separating the kinds, then three short sections. The line it
had to draw is not "documented vs not" but **real frontend vs skeleton probe**,
and the evidence for it was already in the repo:

| | tests in `test/` |
| --- | --- |
| BASIC | five (`comprehensive`, `goto_gosub`, `lexer`, and two edge cases) |
| ada, algol, erlang, fortran, lolcode, whitespace | exactly one `_skeleton` each |

So BASIC gets its own section with a worked example, and the six get a shared one.

### The framing that makes the page worth having

Taken from the umbrella (`feature-esoteric-frontend-probes`), because a list of
curiosities is not worth a page but this is: **the point is not that PXX compiles
Fortran.** The probes exist to prove the shared AST and IR are correct by feeding
them programs shaped unlike anything the mainline frontends emit —
column-sensitive lexing, implicit typing by first letter, dynamic loose casting,
`GOTO`-first control flow. *"Oh, and it compiles Fortran"* is the side effect;
the differential test of the pipeline is the deliverable. That is the same
argument `nil-python.md` already makes for itself, so the page points at it.

The honest summary is stated in the page rather than implied: **it works, it is
one test wide, and it is not going anywhere** — plus "if you want to compile Ada,
use an Ada compiler", which is the sentence a reader needs and the one a list
alone never says.

### Measured on v393 — nothing described here is second-hand

- all six skeletons compile **and run**: `sum correct` (ada), `55` (algol),
  `fact(5) is 120` (erlang), `sum is55` (fortran), `HAI WORLD` (lolcode),
  `Hi` (whitespace);
- BASIC: `test_basic_comprehensive.bas` and `test_basic_goto_gosub.bas` both
  compile and run;
- the page's own BASIC snippet was extracted from the rendered Markdown,
  compiled and run — prints `A` then `looped 3`, with the `SKIPPED` line
  correctly jumped over;
- the quoted `--version` line was string-compared against real output. **It did
  not match on the first pass** — I had dropped the two leading spaces while
  presenting it as program output. Fixed and re-checked; the full `--version`
  block quoted in `cli.md` was verified the same way at the same time.

### One correction to this ticket's own framing

The ticket's table guessed that `ada`, `erlang` and `whitespace` were "not
checked when this was filed". They are all three esoteric probes
(`feature-esoteric-ada`, `feature-esoteric-whitespace`,
`feature-erlang-frontend-scoping` — the last records the skeleton as done and
full-language scoping as untouched). And BASIC is stronger than the ticket
claimed: the umbrella names **Pascal, C, BASIC and Nil-Python** as the first-class
test surface, so BASIC is core, not merely "a real demo target".

The umbrella also lists Zig among the opportunistic set, which is **stale** — Zig
and Rust have had their own tracks since. The page follows CLAUDE.md's current
structure (R and Z experimental) rather than the 2026-07-05 snapshot, and says
their difference from the probes is ambition rather than current support.
