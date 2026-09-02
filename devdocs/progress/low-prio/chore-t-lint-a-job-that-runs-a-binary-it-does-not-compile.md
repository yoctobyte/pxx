---
status: low-prio
track: T
prio: 20
type: chore
blocked-by: []
summary: "The second, weaker half of the split_jobs lint: flag any job that RUNS a /tmp binary no line in that job produces. Prototyped and deliberately NOT shipped — it yields 5-7 candidates depending on how recipe lines are segmented, and every one needs individual adjudication. Shipping it half-tuned would produce exactly the noisy guard that gets muted."
---

# Lint: a job that runs a binary it does not compile

Split out 2026-08-19 by Track T (plexus-T) while closing
[[bug-t-split-jobs-misses-a-tmp-path-reached-through-a-shell-variable]]. That
ticket's primary check — *"flag any job whose text reaches `/tmp` through a
variable"* — is **shipped and enforced** (`tools/testmgr_tmp_var_devtest.py`),
and found a live instance on its first run
([[bug-n-tk-got-files-are-invisible-to-testmgr-privatization]]).

This is its second suggestion, which the parent describes as a *"cheap
corroborating signal"* rather than the main check: **a job that runs a binary it
does not compile is suspicious on its own, independent of how the path is
spelled.**

## Why it was not shipped with the first half

It is not cheap yet. Prototyped against the live `full` job table, and the answer
depends on how a recipe line is cut:

| approach | candidates |
| --- | --- |
| naive (compile = `COMPILE_RE` at line start) | 3 |
| segment each line on `&&` / `;` / `\|\|` first | **7** |

Segmenting made it **worse**, which is the tell that the rule is not yet
well-defined rather than merely untuned. The reason is that a producing
invocation frequently sits mid-line inside a multi-line `if ...; then \` block —
`lib-test#src:test/crtl_exp2.c` compiles `$(TESTTMP)/lib_tk_hello` inside such a
block and then runs it, which is entirely correct and was flagged by both
variants.

The candidates from the segmented run, recorded so the next attempt starts from
data rather than re-deriving them:

```
test-smoke#src:compiler/compiler.pas          /tmp/pascal26-next, /tmp/pascal26-self
lib-test#src:test/crtl_exp2.c                 /tmp/lib_tk_hello +3   <- false positive
test-core#140                                 /tmp/test_ufield_growth26
test-core#src:test/cswitch_noncompound_duff_b207.c  /tmp/stb_sprintf_probe26
test-core#src:test/test_exception_unhandled.pas@3   /tmp/pascal26-next +3
test-core#src:compiler/compiler.pas@2         /tmp/pascal26-threadsafe-self
test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy  /tmp/test_nilpy_pkgimp26
```

The `pascal26-*` ones are self-host chain artifacts produced by a nested `make`
rather than by a compile line, so a correct rule has to model that too.

## Done when

Each candidate is adjudicated — false positive, argued exception, or real
finding — and the rule distinguishes them without a per-case allowlist longer
than the rule itself. If the allowlist ends up longer, that is the answer: the
rule does not carve reality at a joint and should be dropped rather than
maintained.

Low priority on purpose. The enforced half already covers the spelling that has
actually bitten twice; this is the belt to its braces.

## Deprioritised 2026-09-02 — the Track T tooling backlog was cut as a pile

**This ticket is not being called wrong.** It was moved as part of a pile, not
judged individually, and nothing here disputes its finding.

Owner decision. 73 of the 74 open `track: T` tickets were filed between
2026-08-31 and 2026-09-02, 58 on one day. The pile was too large to work through
and returned almost nothing, and a ticket nobody will fix does not sit neutrally
— it stays in the ranker forever at zero value, which is the argument CLAUDE.md
already makes for a terminal folder over a low prio.

Four were kept in the ranker on a purely structural test — an active umbrella or
a hard `blocked-by:` edge from live work:
`umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**Kept, not deleted, for two reasons:** so the finding is not rediscovered and
refiled from scratch by the next agent who trips over it, and so it can be pulled
back if what it touches becomes load-bearing.

**To revive it:** move it to the owning lane's backlog, set `status: backlog`,
and say in the ticket WHAT CHANGED to make it matter now. Restoring it because it
reads well is how the pile comes back.
