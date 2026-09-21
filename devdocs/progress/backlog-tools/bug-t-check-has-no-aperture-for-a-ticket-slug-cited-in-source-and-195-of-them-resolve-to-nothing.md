---
slug: bug-t-check-has-no-aperture-for-a-ticket-slug-cited-in-source-and-195-of-them-resolve-to-nothing
type: bug
track: T
prio: 40
status: open
summary: "`progress.sh check` reads tickets and never reads SOURCE, so a ticket slug cited in a compiler or library comment is unchecked — and 195 distinct ones in `compiler/**` + `lib/**` resolve to no ticket. The common shape is not a missing ticket but a RE-WORDED one: `pil.pas` cites `...silently-turns-its-own-constructor-into-a-self-call` where the filed slug is `...cannot-be-constructed-from-outside-that-unit`, same bug, different words, so a reader who greps the cited slug finds nothing and concludes the ticket was never filed. The check's DANGLING-LINK aperture already does exactly this job for wiki-links inside ticket bodies; the gap is only which files it opens. Found because I landed a 196th in 3d3d90a2d and the check went green over it."
---

# `check` has no aperture for a ticket slug cited in SOURCE

Source comments cite ticket slugs constantly and the convention is a good one —
`feature-nilpy-dotted-package-imports`, `bug-nilpy-omitted-variant-default-segfaults`
and ~2100 others resolve correctly. Nothing verifies them.

`check` already has the right idea one folder over: **DANGLING-LINK** reports a
`[[wiki-link]]` in a ticket body whose prefix looks live but resolves to no
ticket, and its text is careful about the five repairs (rename, planned-never-
filed, delivered-under-another-name, merged, never-a-ticket). **All five apply
verbatim to a source comment.** The aperture just never opens a `.pas` or `.inc`.

## How it was found, which is the part worth keeping

Not by auditing. I wrote a comment in `compiler/pyparser.inc` citing
`bug-n-a-stdlib-class-folds-onto-a-same-named-function-and-silently-evaluates-to-its-result`,
a slug I had composed while writing the comment and never filed — I had FIXED
the bug instead, which is what this repo asks for. `check` ran green. The
citation is unreachable for every future reader and no instrument says so.

**A fix-don't-file culture manufactures this steadily.** The natural way to
record why a line is the way it is, while fixing rather than filing, is to cite
the bug in a comment — and there is then no ticket for that slug to resolve to.

## The measurement, with its population, so a re-run can disagree usefully

Tree `3d3d90a2d`. Population **`compiler/**` + `lib/**`, `.pas` and `.inc` only**.
`tools/**` is EXCLUDED and must stay excluded: `progress_near_corpus.py` is a
corpus of example slugs for the near-dup checker and `*_devtest.sh` carry
fixtures like `bug-a-a-throwaway`, none of which are citations. Slug shape is
`(bug|feature|task|decide|refactor|perf)-` plus three or more dashed segments,
matched against the 4959 `.md` filenames under `devdocs/progress/*/`.

    distinct slug-shaped citations : 2472
    resolve exactly                : 2119
    prefix of a real slug          :  158   <- LINE-WRAPPED in a comment, not a defect
    no real slug begins with it    :  195   <- the finding

**The 158 are not a bug and must not be counted as one.** A comment wraps
mid-slug and the regex sees a prefix. Any re-implementation that skips this
split will report 353 and be wrong by 45%.

Worst files: `pyparser.inc` 58, `pasparser_expr.inc` 18, `builtin/pylib.pas` 17,
`symtab.inc` 11, `ir.inc` 11, `pasparser_decl.inc` 11.

## The 195 are NOT mostly missing tickets, and the repair differs

Two sampled, both RE-WORDINGS of tickets that exist:

- `lib/rtl/pil.pas` cites `bug-a-a-class-named-after-a-used-unit-silently-turns-its-own-constructor-into-a-self-call`;
  filed as `bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit`.
- `bug-a-a-method-pointer-record-is-hard-sized-on-32-bit-targets`; filed as
  `bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets`.

So the dominant repair is **correct the spelling**, not **file the ticket** —
and a checker that reports these as "missing tickets" would send someone to
re-file work that is already tracked. Report them as UNRESOLVABLE CITATIONS and
let the reader pick among the five DANGLING-LINK repairs.

**The sample is 2 of 195 and the proportion is NOT established.** Do not quote
a split between renames, never-filed and delivered-elsewhere until someone has
classified a real sample; the only measured claim here is that 195 do not
resolve and that at least two are renames.

## Why 40 and not higher

Nothing is mis-ranked and no program misbehaves — a stale citation costs a
reader a grep and the wrong conclusion. It earns a number above the floor
because the population is large, it grows every time someone follows this repo's
own fix-don't-file rule, and the failure is silent in the direction of a reader
deciding a bug was never reported.

## What would retire this

`check` opening `compiler/**` and `lib/**` for slug-shaped tokens and reporting
the unresolvable ones under the existing DANGLING-LINK wording. Two things it
must get right or it is worse than nothing:

- **Exclude the prefix-of-a-real-slug case**, or it reports 45% noise on its
  first run and teaches everyone to ignore it.
- **Exclude `tools/` corpora and devtest fixtures by path**, not by heuristic;
  they are deliberately full of fake slugs, and a checker that reds on its own
  test corpus is born red.

Positive control: **`lib/rtl/pil.pas`'s
`bug-a-a-class-named-after-a-used-unit-silently-turns-its-own-constructor-into-a-self-call`
must be reported.** Verified unresolvable at 3d3d90a2d, with the real ticket
(`...cannot-be-constructed-from-outside-that-unit`) sitting right beside it, so
it exercises the rename case rather than the never-filed one.

**Deliberately NOT the instance that prompted this ticket.** Mine —
`compiler/pyparser.inc`'s `bug-n-a-stdlib-class-folds-onto-a-same-named-function-...` —
is being REPAIRED in the same lane, so a control pointing at it would pass by
being fixed rather than by the checker working. A control has to be something
the fix does not touch. The tree also holds ~193 others if this one is ever
repaired; re-derive from the census above rather than picking a fresh one from
memory.
