# Track U digest — 23 open decisions

**Measured at `64758a5c2`, 2026-08-30.** This page rots faster than most: it
quotes ticket prios, dependency edges and a branch divergence that all move.
Regenerate rather than trust it — `ls devdocs/progress/*/decide-*.md` is the
population, and every claim below names how it was checked.

Track U is the one lane no agent can work, and the one that unblocks the ranked
chain behind it. **Ordered by what the answer releases, not by the decision's own
prio** — the first four are worth more than their numbers suggest.

**Checked against `decided/` (116 entries): none of the 23 is already answered.**
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

### `decide-what-happens-to-the-136-commit-rust-branch` (p60) and `decide-should-the-rust-topic-branch-be-retired-onto-master` (p45)

**These are one question, and its premise has moved.** The first says *"origin/rust
holds 136 commits of divergent work while origin/master is 222 ahead"*.

Measured today:

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
*"merge or drop at most 14, most of which are ticket paperwork"*. Master pulling
ahead 222 → 418 in the meantime says the branch is being kept in sync **into**
rust and is not accumulating stranded work.

**Both tickets should be re-filed as one, against the measured divergence.** The
decision they ask for — does Track R work on master like everyone else — is still
real and still yours; the 136-commit framing is what is stale, and it makes the
question look far more expensive than it is. `decide-should-the-rust-topic-branch-be-retired-onto-master`
already recommends **option 1 (retire onto master)** and argues Track R's work has
not been destabilizing.

### Verified NOT stale — the code still matches the ticket

Three that looked cheap to falsify and were not:

- `decide-should-writeableconst-off-be-honoured` — `grep -ri writeableconst compiler/` still returns **nothing**. The directive genuinely does not exist.
- `decide-does-the-legacy-gtk-alias-still-point-at-gtk-2` — `pasparser_proc.inc:2503-2505` still maps `gtk` → `gtk-x11-2.0` and `gtk3_c` → `gtk-3`.
- `decide-which-gtk-a-bare-gtk-gtk-h-means` — same site, same split.

---

## Answerable in one word — the substance is already settled

- **`decide-is-binds-the-cpyext-runtime-the-ratified-extension-module-check`** (p30). Not really a fork: a prior decision ratified `PyInit_<name>`, the implementation shipped *"binds the cpyext runtime"* after measuring that the ratified test held in zero real cases, and nobody recorded the substitution. The ticket recommends **option 1 — ratify what shipped** and says so plainly: *"the substance was decided; only the paperwork is open."* **Say yes and it closes.**
- **`decide-nilpy-deepcopy-over-the-container-subset`** (p40). Recommendation **A**, and then *delete the "DELIBERATELY ABSENT" paragraph rather than leaving two documents disagreeing.* The second half is the real content — this is a docs-consistency fix wearing a decision's clothes.

---

## Process decisions — these change how every lane works

Answering these costs one sentence each and changes the loop for all agents, so
they are cheap and high-leverage. None declares a dependency edge, which is why
they do not surface in the ranker.

| decision | prio | fork | recommendation |
| --- | --- | --- | --- |
| `decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop` | 55 | pxx accepts a call above its definition; FPC — which bootstraps this compiler — does not. Does the canary become mandatory? | **option 1**, with the caveat stated: it relies on a lane recognising its own edit shape, and one lane's edit was exactly that shape and went unnoticed for days |
| `decide-should-forwardlint-join-the-mandatory-per-fix-loop` | 50 | same family — does forwardlint join the three-line loop? | **option 1, narrowly** — the "do not widen" rule exists to stop ten-minute suites, and this is not one |
| `decide-t-refuse-unscoped-pattern-kills-in-a-hook` | 45 | a PreToolUse hook refusing bare-pattern `pkill`/`killall`. **A `.claude/` change binding every agent on this box, so explicitly yours** | **C — do not add it, revisit if it recurs**; the cause is unproven and two landed layers already remove the bad instruction |
| `decide-two-devdocs-directories-make-a-wrong-grep-look-like-a-refutation` | 30 | `devdocs/dev/` (50 files) and `devdocs/developer/` (58) both hold internal docs; a grep in the wrong one reads as a refuted citation | **option 1 (consolidate)**, with two stated conditions |
| `decide-t-should-a-skip-close-an-open-regression` | 25 | `reg_open` counts red → skip as FIXED, so a regression closes when a box merely stops running the job | ticket describes it as a deliberate existing trade; needs your ruling on which error you prefer |

**Note the pattern**: two of these (`fpc-seed-canary`, `forwardlint`) are the same
question asked twice about different checks — *what may join the mandatory
per-fix loop?* A general answer would close both and pre-answer the third time it
comes up. Worth deciding the **rule** rather than the two instances.

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
have quoted it rather than formed my own — 14 of the 23 carry one, and the filer
had the context. The two things I did add are **measurement**: the `decided/`
cross-check (none already answered) and the rust-branch divergence (122 of 136
already on master), because both change what is worth reading and neither was
visible from the ticket text.
