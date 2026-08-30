# Track U digest

## CURRENT QUEUE — 33 open, measured 2026-08-30 ~11:1x

**This section supersedes the "21 distinct questions" page below**, which was
measured at 01:10 and covers 20 of these. **Thirteen are newer than it** and are
marked NEW; the older page's prose on the other twenty still stands.

**Read the warning first if you are working these in `~/frank-user`: that
checkout is 1469 commits behind `origin/master`, last commit 27 hours old.** Six
of the thirteen NEW tickets do not exist in that tree at all, and several of the
older twenty have been edited since. `git pull --rebase` there before reading
anything.

**Ordered by prio, with what the answer formally releases.** Treat `unblocks` as
a FLOOR, not a count: it reads `blocked-by:` frontmatter only, and this board's
recurring defect is dependencies stated in prose that never became edges. Four
of the six ranked chains that stalled overnight were prose-only.

| prio | unblocks | ticket |
| ---: | ---: | --- |
| 70 | 2 | `decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal` |
| 70 | 0 | `decide-revisit-object-types-rtl-generics-fired-the-trigger` — **NEW** |
| 70 | 0 | `decide-the-ticket-lock-is-too-heavy-for-a-per-minute-commit-loop` — **NEW** |
| 65 | 1 | `decide-is-the-2026-07-12-esp-park-still-in-force` — **NEW** |
| 62 | 0 | `decide-nilpy-what-version-does-sys-version-info-claim` |
| 60 | 0 | `decide-does-a-withdrawn-pin-leave-a-trace-and-is-its-version-number-reused` — **NEW** |
| 60 | 1 | `decide-does-nilpy-random-seed-itself-at-import` |
| 60 | 0 | `decide-does-track-r-work-on-master-like-every-other-lane` |
| 60 | 0 | `decide-nilpy-runtime-tax-serialise-the-image-or-defer-the-bodies` — **NEW** |
| 60 | 0 | `decide-the-licensing-page-says-no-license-yet-and-the-repo-has-one` — **NEW** |
| 55 | 1 | `decide-install-qemu-system-and-a-freebsd-image-on-plexus` |
| 55 | 0 | `decide-may-a-lane-be-given-the-full-suite-escape-for-four-corpus-builds` — **NEW** |
| 55 | 0 | `decide-nilpy-ranking-is-shaped-by-a-low-dependency-sample` |
| 55 | 0 | `decide-settextbuf-needs-buffered-text-io-or-stays-missing` |
| 55 | 0 | `decide-should-forwardlint-join-the-mandatory-per-fix-loop` |
| 55 | 0 | `decide-should-forwardlint-run-in-the-build-not-only-the-gate` — **NEW** |
| 55 | 0 | `decide-what-a-reduced-compiler-must-still-self-host` — **NEW** |
| 55 | 1 | `decide-which-gtk-a-bare-gtk-gtk-h-means` |
| 50 | 0 | `decide-does-the-legacy-gtk-alias-still-point-at-gtk-2` |
| 50 | 0 | `decide-what-should-a-shared-gate-do-when-its-watched-number-grows-from-normal-work` — **NEW** |
| 45 | 0 | `decide-t-refuse-unscoped-pattern-kills-in-a-hook` |
| 40 | 0 | `decide-c-crtl-rand-max-is-conforming-but-breaks-real-code` |
| 40 | 0 | `decide-nilpy-deepcopy-over-the-container-subset` |
| 40 | 0 | `decide-two-threading-docs-disagreed-for-seven-weeks` — **NEW** |
| 30 | 0 | `decide-is-binds-the-cpyext-runtime-the-ratified-extension-module-check` |
| 30 | 0 | `decide-is-real-a-double-or-fpcs-80-bit-extended` |
| 30 | 0 | `decide-two-devdocs-directories-make-a-wrong-grep-look-like-a-refutation` |
| 30 | 0 | `decide-where-a-persistent-fpc-trunk-oracle-lives` |
| 25 | 1 | `decide-posix-master-vs-fpc-named-master-for-the-socket-facades` — **NEW** |
| 25 | 0 | `decide-release-signing-key-custody` |
| 25 | 1 | `decide-t-per-assertion-subjects-or-accept-the-file-level-label` |
| 25 | 0 | `decide-t-should-a-skip-close-an-open-regression` |
| 20 | 0 | `decide-should-writeableconst-off-be-honoured` |

### Clusters — several of these are one answer wearing three slugs

Answering a cluster head usually settles the rest, and reading them together is
much cheaper than reading them apart:

- **GTK, three tickets**: `which-gtk-a-bare-gtk-gtk-h-means` (p55, unblocks 1),
  `does-the-legacy-gtk-alias-still-point-at-gtk-2` (p50), and the GTK 2-vs-3
  install question already recorded as an owner item. One answer.
- **forwardlint, two tickets**: `join-the-mandatory-per-fix-loop` and
  `run-in-the-build-not-only-the-gate` (both p55). Same subject, two placements;
  answering the first constrains the second.
- **Gate policy, three tickets**: `may-a-lane-be-given-the-full-suite-escape`
  (p55), `what-should-a-shared-gate-do-when-its-watched-number-grows` (p50),
  `t-refuse-unscoped-pattern-kills-in-a-hook` (p45). All three are "how strict is
  the shared gate, and who may step outside it".
- **Track R's home, two tickets**: `does-track-r-work-on-master-like-every-other-lane`
  (p60) plus the two rust-branch questions filed overnight. The 136-commit branch
  is the real subject.
- **Pin bookkeeping, two tickets**: `does-a-withdrawn-pin-leave-a-trace` (p60,
  coordinator-filed) and `t-should-a-skip-close-an-open-regression` (p25).

### If you only answer three

`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`
(p70, formally unblocks 2, and it is what has the wasm lane idle),
`decide-revisit-object-types-rtl-generics-fired-the-trigger` (p70 — it is the
sole live gate on `feature-pascal-corpus-expansion` [P p75], the top-ranked
Pascal item, and that dependency is a dated `Status:` line rather than an edge),
and `decide-is-the-2026-07-12-esp-park-still-in-force` (p65, heads Track S's
whole ranked queue and every agent is told not to claim it).

---

## Earlier page — 21 distinct questions, measured at 01:10

**Measured at `64758a5c2`, 2026-08-30. Revised the same day** after the triage
found duplicates: **23 tickets were 21 questions**, and the two collapses are
described below. The count that matters to whoever works this lane is *distinct
questions*, not open files — a duplicate costs a full read before it costs
nothing. This page rots faster than most: it
quotes ticket prios, dependency edges and a branch divergence that all move.
Regenerate rather than trust it — `ls devdocs/progress/*/decide-*.md` is the
population, and every claim below names how it was checked.

Track U is the one lane no agent can work, and the one that unblocks the ranked
chain behind it. **Ordered by what the answer releases, not by the decision's own
prio** — the first four are worth more than their numbers suggest.

**Checked against `decided/` (116 entries): none of the 23 was already answered.**
No slug overlap, no topic overlap.

---

## Read these four first — a low-prio answer releases a higher-prio chain

| decision | its prio | releases | at |
| --- | --- | --- | --- |
| **`decide-t-per-assertion-subjects-or-accept-the-file-level-label`** | 25 | `bug-t-a-one-ulp-move-turns-the-fleet-red-and-outranks-its-own-prio` | **50** |
| **`decide-release-signing-key-custody`** | 25 | `feature-release-checksums-repro` | **50** |
| **`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`** | 40 | `feature-a-wasm32-sys-intrinsics-and-ir-syscall-lowering` | **60** |
| **`decide-which-gtk-a-bare-gtk-gtk-h-means`** | 55 | `feature-c-gtk3-header-final-wiring` | 55 |

**`release-signing-key-custody` is the one to answer first if you answer only
one**, because part of it needs no decision at all: the ticket recommends
**minisign, with the checksum + reproducible-build half shipping first as its own
step**. That half carries no secret and is agent-work — it can start tonight and
delivers most of the value. Only the key custody itself needs you. *One sentence
from you unblocks a p50 at the head of Track A's queue and costs nothing if you
defer the key.*

`t-per-assertion-subjects` is the same shape: a p25 label question gating a p50
about the fleet going red on a one-ulp float move. The ticket's own finding is
that the existing mechanism **labels a whole job while every motivating file
mixes an accuracy nit with a real fault** — so "accept the file-level label" is
not a neutral option, it keeps a mechanism with zero adopters that structurally
cannot gain any.

---

## STALE — re-measure before spending attention

### The rust branch — **COLLAPSED**, and its price was the reason it sat

`decide-what-happens-to-the-136-commit-rust-branch` (p60) and
`decide-should-the-rust-topic-branch-be-retired-onto-master` (p45) asked one
question, and both priced it off a divergence that has moved. They are now one
ticket: **`decide-does-track-r-work-on-master-like-every-other-lane`** (p60).
Both originals are preserved in `rejected/` with redirect notes — their analysis
is good and only the numbers rotted.

The p60 said *"origin/rust holds 136 commits of divergent work while
origin/master is 222 ahead."* The p45 said *"8 ahead and 57 behind."* Both are
stale, in opposite directions. Measured today:

```
git rev-list --left-right --count origin/master...origin/rust   ->  418  136
git cherry origin/master origin/rust | grep -c '^-'             ->  122   (equivalent already on master)
git cherry origin/master origin/rust | grep -c '^+'             ->   14   (no equivalent)
```

**122 of the 136 are already on master.** And 14 is an upper bound, not the
answer: `git cherry` matches by patch-id, so anything rebased with a different
resolution shows as absent. Two spot-checks of the 14 are demonstrably present —
the `{$NILCHECKS}` docs are in `docs/reference/directives.md` today, and the
for-loop bounds fix is `8b35e88fa` on master.

So the fork is no longer *"what do we do with 136 stranded commits"*; it is
*"does Track R work on master, and do we merge or drop at most 14 mostly-paperwork
commits"*. Master pulling ahead 222 → 418 meanwhile says the branch is being kept
in sync **into** rust and is not accumulating stranded work.

**The finding underneath is worth more than the correction.** Nobody opens a
136-commit merge decision at 3am. *A number that rotted made a cheap question
look expensive, and the cost estimate is what people triage on, not the
question.* A U ticket does not need to be wrong to be unanswerable; it only needs
to be priced wrong — and the old slug carried the stale number **in the slug**,
the one place a reader cannot skip. That is why the survivor has a new slug
rather than an edit.

### Verified NOT stale — the code still matches the ticket

Three that looked cheap to falsify and were not:

- `decide-should-writeableconst-off-be-honoured` — `grep -ri writeableconst compiler/` still returns **nothing**. The directive genuinely does not exist.
- `decide-does-the-legacy-gtk-alias-still-point-at-gtk-2` — `pasparser_proc.inc:2503-2505` still maps `gtk` → `gtk-x11-2.0` and `gtk3_c` → `gtk-3`.
- `decide-which-gtk-a-bare-gtk-gtk-h-means` — same site, same split.

---

## Answerable in one word — the substance is already settled

**One item, not two.** The first draft of this page listed a second and was
wrong; the correction is below, because a triage that mislabels a live fork as
paperwork does more damage than one that misses a duplicate.

- **`decide-is-binds-the-cpyext-runtime-the-ratified-extension-module-check`** (p30). Not really a fork: a prior decision ratified `PyInit_<name>`, the implementation shipped *"binds the cpyext runtime"* after measuring that the ratified test held for only 3 of the 6 real units, and nobody recorded the substitution. It is shipped, pinned in v391, and now documented on the public website. The ticket recommends **option 1 — ratify what shipped**: *"the substance was decided; only the paperwork is open."* **Say "ratified" and it closes; no code moves.** Re-priced in the ticket itself so the next reader sees the cost before the argument.

### CORRECTION — `decide-nilpy-deepcopy-over-the-container-subset` (p40) is a real fork

This page first called it *"a docs-consistency fix wearing a decision's
clothes"*, on the strength of the tail of its recommendation (*delete the
"DELIBERATELY ABSENT" paragraph*). **That reads the consequence of choosing A as
if it were the question.** It is not:

- The fork is whether `copy.deepcopy` **exists at all** over the container
  subset — roughly 40 lines of NilPy with an `id()`-keyed memo table — and
  option B (keep the loud absence) is live and is a **previous author's
  explicit, reasoned decision**. The filer says so: *"it overrides a documented
  decision, so it is the owner's call and not mine."*
- Neither half is mine to do. The paragraph is at **`lib/rtl/mimic_copy.py:29`**
  — a library file, Track **B**'s lane. Not `docs/**`. I could not have taken it
  if the label had been right.

The real shape: **upward compatibility (an ordinary CPython program that
deepcopies a nested dict does not run) against a documented deliberate absence.**
That is exactly the kind of call Track U exists for. It stays.

---

## Process decisions — these change how every lane works

Answering these costs one sentence each and changes the loop for all agents, so
they are cheap and high-leverage. None declares a dependency edge, which is why
they do not surface in the ranker.

| decision | prio | fork | recommendation |
| --- | --- | --- | --- |
| `decide-should-forwardlint-join-the-mandatory-per-fix-loop` **(collapsed, was two)** | 55 | `make compiler/pascal26` compiles with **pxx**, so the loop and the fixedpoint are blind **by construction** to what pxx accepts and FPC rejects — and FPC is the seed. Does the 4.1s lint that models FPC's resolution join the loop? | **option 1, narrowly** — the "do not widen" rule exists to stop ten-minute suites, and its own rationale does not reach a seconds-long check covering a hole the loop cannot see |
| `decide-t-refuse-unscoped-pattern-kills-in-a-hook` | 45 | a PreToolUse hook refusing bare-pattern `pkill`/`killall`. **A `.claude/` change binding every agent on this box, so explicitly yours** | **C — do not add it, revisit if it recurs**; the cause is unproven and two landed layers already remove the bad instruction |
| `decide-two-devdocs-directories-make-a-wrong-grep-look-like-a-refutation` | 30 | `devdocs/dev/` (50 files) and `devdocs/developer/` (58) both hold internal docs; a grep in the wrong one reads as a refuted citation | **option 1 (consolidate)**, with two stated conditions |
| `decide-t-should-a-skip-close-an-open-regression` | 25 | `reg_open` counts red → skip as FIXED, so a regression closes when a box merely stops running the job | ticket describes it as a deliberate existing trade; needs your ruling on which error you prefer |

**These were two tickets and are now one.**
`decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop` (p55) asked the same
thing from the other end — its **option 4 was the other ticket's option 1**, same
tool, same cost, same fork — and the argument that kept it out (a permanent
`LowerCase` note on a clean tree) was fixed in `7aba316be`. Its evidence log is
the richest thing either had and is preserved intact in `rejected/`, cited by the
survivor: **five measured instances** of the loop green while the FPC seed build
was red, the **empirical disproof** of the "just watch for that edit shape"
option (the lane missed both of its own instances), and the positional-guard
finding — *a guard whose correctness depends on relative position is re-broken by
any edit that moves either side, and the person who added it will remember adding
it.*

**I deliberately did not generalise it to "what is the rule for loop
membership?"**, though it is tempting and the question will recur. This page's
own finding is that decisions sit when they are **priced wrong**, and turning a
concrete yes/no about a verified 4-second lint into an abstract policy question
raises the price of the one decision here that is currently cheap — the same
mistake the rust ticket made by accident. The general rule is offered inside the
ticket as an optional second sentence the owner may take or leave, not as a
precondition.

---

## Product / semantics claims — these are visible to users

| decision | prio | the fork | recommendation |
| --- | --- | --- | --- |
| `decide-nilpy-what-version-does-sys-version-info-claim` | **62** | `sys.version_info` is absent. Any number we answer silently steers third-party libraries down a code path | **B — a recent 3.x we can defend**, so the modern branch of a version test is the branch we implement |
| `decide-nilpy-ranking-is-shaped-by-a-low-dependency-sample` | 55 | a fourth corpus (reportlab, 421 files) shares **none** of its 30 first walls with the previous three, because 89% of its failures are missing library surface | **no recommendation stated** — this one reshapes NilPy's whole ranked queue and is the most consequential unanswered question on the page |
| `decide-settextbuf-needs-buffered-text-io-or-stays-missing` | 55 | `textfile.pas` has no buffering at all — one `PalRead` syscall per byte | **(b) now, (a) as its own ticket ranked on the performance case**, because `SetTextBuf` is the least valuable reason to build buffering |
| `decide-does-nilpy-random-seed-itself-at-import` | 60 | CPython seeds from entropy; NilPy from a fixed constant so failures reproduce. Collides with upward-compatibility | **option 2**, falling back to 1 — upward compatibility is the stronger claim |
| `decide-c-crtl-rand-max-is-conforming-but-breaks-real-code` | 40 | `RAND_MAX` 32767 is C99-conforming; every mainstream libc uses 2147483647 and real programs branch on it | none stated |
| `decide-is-real-a-double-or-fpcs-80-bit-extended` | 30 | `Real` is a 64-bit Double here, FPC's is x87 80-bit Extended; agreeing means implementing Extended | none stated — **and note the standing ruling: float formatting parity is Track F, low prio by definition** |
| `decide-should-writeableconst-off-be-honoured` | 20 | the directive is unimplemented; typed constants are unconditionally writable, which is FPC's *default* | none stated |

**`nilpy-ranking-is-shaped-by-a-low-dependency-sample` is the one I would put your
attention on after the four at the top.** It does not block a named ticket — it
calls into question the ordering of an entire lane's queue, which is worse. If
the sample that produced NilPy's ranking systematically missed the failure mode
that dominates a real dependency-heavy program, then the work being done first is
not the work that matters most, and no dependency edge will ever say so.

---

## Resource requests — these need your machine, not your judgement

- **`decide-install-qemu-system-and-a-freebsd-image-on-plexus`** (p55, releases a p20). Needs `qemu-system` installed and a multi-GB OS image fetched. A yes/no about the box.
- **`decide-where-a-persistent-fpc-trunk-oracle-lives`** (p30). A trunk build is ~4 min and ~1 GB, must live outside the repo, and installing into `~` needs your say-so. Recommendation: **C if a persistent oracle is wanted, A if the yield estimate holds** — and the filer notes T's own view is that A is defensible.

Both are legitimately Track U: no amount of agent reasoning substitutes for
consent to install things on your machine.

---

## What this digest is not

It does not re-litigate any decision. Where a ticket states a recommendation I
have quoted it rather than formed my own — 14 of the 23 carried one, and the
filer had the context. What I added is **measurement**, in three places, because
each changes what is worth reading and none was visible from the ticket text:

1. the `decided/` cross-check — none of the 23 was already answered, which is
   worth as much as a hit would have been *because* I expected at least one;
2. the rust-branch divergence — 122 of 136 already on master, and the two
   spot-checks that show 14 is an upper bound;
3. the duplicate collapse — 23 tickets, 21 questions.

**And one thing it corrects.** The first draft called the NilPy `deepcopy` ticket
a docs-consistency fix. It is a live fork over a previous author's reasoned
decision, in a Track B file, and the correction is in place above rather than
quietly fixed. Compression is this page's whole value and it is also its whole
risk: a summary that mislabels a real question as paperwork removes it from the
owner's attention as effectively as losing the ticket would.

**Two things I deliberately did not do**, both for the same reason — collapsing
two real questions into one is worse than leaving both open: I did not merge any
pair whose forks differ, and I did not generalise the loop-membership decision
into a policy question.
