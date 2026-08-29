---
track: D
prio: 20
type: docs
blocked-by: []
summary: "`pxx --version` prints twelve frontends — pascal c nilpy rust zig ada basic fortran algol erlang lolcode whitespace — and `docs/**` mentions five. A reader who runs the flag sees Ada, Fortran, Algol, Erlang, BASIC, LOLCODE and whitespace nowhere in the documentation, with no way to tell a demo target from an esoteric probe. Decide what the public docs say about the other seven."
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
