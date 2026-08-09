---
track: U
prio: 50
type: decide
status: resolved
resolved: 2026-08-09
summary: "Several ranked Track B tickets need a third-party package present on the box — as a differential oracle (reportlab) or as the compile target itself (html5lib, tinycss2, webencodings). None is installed here and fetching one is a supply-chain action, so the lane is stalled on a policy answer, not on work"
---

## DECIDED 2026-08-09 — yes, when the library is named in project docs; use the existing tool

**User's call:** if a third-party library is discussed and named in the project
documentation, an agent may fetch it. The mechanism already exists —
`tools/install_lib_candidates.sh`.

**And this question was already largely answered**, which I should have checked
before filing: [[decide-3rd-party-vendor-vs-fetch]] settled the policy on
2026-08-01 — corpus stays fetch-gitignored, vendoring only for small
dependency-grade exceptions. My four options re-litigated a decided policy. The
lesson for next time is to search `decided/` before opening a `decide-*`, not
only `backlog/`.

What was genuinely open, and is now closed, is the narrower question: may an
agent RUN that tool on its own initiative. Yes, for libraries the docs name.

## The tool, and the one real gap

`tools/install_lib_candidates.sh` fetches into `library_candidates/`, which is
gitignored; the script refuses to run if that ever stops being true, so a fetched
tree cannot be committed by accident. Each candidate is pinned to an upstream
commit (or version + SHA256) and gets a `PROVENANCE.md`. That is a stronger
mechanism than the "curated vendored corpus" I recommended above — same
reproducibility, none of the in-tree weight.

Its candidate list is entirely C: lua, tiny-regex-c, freebsd-regex, sqlite,
c-testsuite, fpc-testsuite, zlib, tcc, cjson, stb, cglm, enet, zengl, quickjs,
duktape, fcl-json. **There are no Python targets**, so the two tickets that
prompted this still cannot fetch what they need:

| ticket | needs |
| --- | --- |
| [[feature-nilpy-codecs-shim]] | `webencodings`, `tinycss2`, `html5lib` |
| [[feature-lib-reportlab-fidelity-vs-oracle]] | `reportlab` (+ a glyph-box reader) |

All four are named in [[feature-nilpy-thirdparty-libraries-as-targets]] and the
reportlab ticket respectively, so they clear the bar. Adding them as pinned
candidates is the follow-up that unblocks both.

# May an agent fetch third-party sources/packages, and under what rule?

- **Type:** decide — Track U
- **Opened:** 2026-08-09
- **Filed by:** Track B, hitting it twice in one session while working the
  ranked queue. Escalated rather than guessed.

## The fork

Two ranked Track B tickets cannot be *measured* on this box:

| ticket | needs | present? |
| --- | --- | --- |
| [[feature-lib-reportlab-fidelity-vs-oracle]] | CPython + `reportlab` (+ `pdfplumber` for glyph boxes) | **no** (`pdftotext` yes) |
| [[feature-nilpy-six-and-warnings-shims]] | `html5lib`, `tinycss2`, `webencodings` sources to re-run the 48-file scan its gate names | **no** (`six.py` itself IS present, in dist-packages) |

Both are *differential* tickets, and this repo's whole debugging doctrine is
measure-against-an-oracle rather than reason. Without the oracle the honest
options are to write the code unverified — exactly the "plausible-looking output
is where the expensive bugs live" failure this project keeps naming — or to
leave ranked work parked.

Same question again for the wider library campaign
([[feature-nilpy-thirdparty-libraries-as-targets]]): "compile real-world code
as-is" needs the real-world code to be *on the box*, and it keeps not being.

## Why this is not an agent's call

Fetching a package is outward-facing and it is a supply-chain action — the same
reason [[frank2-website-deploy-no-autodeploy]] keeps the website deploy manual.
An agent deciding on its own to `pip install` from PyPI, or to `curl` a tarball,
is a policy change made by whoever happened to be holding the lane that hour.

## Options

1. **Nothing fetched, ever.** These tickets get re-tagged as "needs a prepared
   box" and drop out of the ready queue until the user provisions one. Honest,
   and it stops the queue advertising work that cannot be done.
2. **A vendored corpus, curated by the user.** The user drops the sources under
   `lib/vendor/` or a `corpus/` tree once, pinned and reviewed, and agents only
   ever read what is already committed. Matches how `lib/vendor/pdfgen` already
   works, keeps the supply chain reviewed, and makes the scans reproducible
   across boxes and across time — the 48-file scan currently is not, since it
   was measured against whatever happened to be installed wherever it was run.
3. **Agents may fetch, into a scratch dir, read-only, never committed**, with the
   exact command recorded in the ticket. Fastest; weakest provenance; a scan run
   twice may not measure the same bytes.
4. **Per-request approval.** An agent files a "fetch X" ask and waits. Safe but
   it serialises the library campaign on the user's attention, which is the
   thing Track U is supposed to reduce.

## Recommendation

**Option 2**, with option 4 as the way each new package enters it. A vendored,
pinned corpus is the only one that makes a differential result *reproducible*,
which is the entire point of a differential ticket — and it costs the user one
review per package rather than one per session.

Worth deciding as one policy rather than per ticket: the same question will be
asked by every future compat/library ticket, and the ranked queue currently has
several sitting behind it.

## What is NOT blocked by this

`mimic_six` / `mimic_warnings` can still be *written* — `six.py` is on the box,
so the semantics have an oracle. Only the "re-run the 48-file scan" half of that
ticket's gate needs the answer.
