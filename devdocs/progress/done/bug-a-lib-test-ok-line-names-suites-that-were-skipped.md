---
track: A+T
prio: 45
type: bug
blocked-by: []
summary: "lib-test's closing `lib-test ok (... + synapse-ssl ...)` line enumerates suites unconditionally, including ones an `ifeq ($(wildcard external/synapse),)` guard skipped. Measured 2026-08-29 in a tree with no external/synapse: the recipe printed `SKIP lib_synapse ...` at log line 441 and then `lib-test ok (... + synapse-ssl)` at line 1197. The skip is loud, but it is 750 lines above the summary; the summary is the LAST line, which is what a human reads and what job_reason() records as the tail. A green claiming a component that did not run."
status: done
---

# `lib-test ok (…)` names suites that were skipped

Found 2026-08-29 while checking whether the 221 converted assertions in
`lib-test` actually executed, rather than inferring it from `EXIT=0`.

217 of the 221 appeared in the log. The 4 absent were all `lib_synapse*`, and
they were skipped correctly and **loudly**:

```
441:  SKIP lib_synapse + lib_synapse_transitive_unit -- external/synapse absent;
      fetch it with: tools/install_externals.sh
```

That guard is deliberate and well-reasoned (see the comment above it, and
`bug-b-lib-test-unrunnable-in-a-fresh-clone-no-synapse-fetch`): a fresh clone
should skip rather than fail, so Track B's gate stays runnable.

The defect is the closing line, 750 lines later:

```
1197: lib-test ok (sudoku exact + collections + … + x509 + tls-seam + … +
      reportlab-diff + synapse-ssl) against stable v390
```

`synapse-ssl` did not run. Neither did `lib_synapse` or
`lib_synapse_transitive_unit`. The summary enumerates the suites the rule
*contains*, not the ones it *executed*.

## Why the loud skip does not save it

Distance. The skip is at line 441 of a 1197-line log; the claim is the last
line. Those are read by different readers:

- a human reads the **last** line, which is the whole point of a summary;
- `job_reason()` takes the **log tail** by deliberate design — so for any
  consumer downstream of this rule, the loud skip is not in the record at all
  and the enumeration is.

So a tree with no `external/synapse` produces a green that names a component
that did not run, and nothing at the point of reading says otherwise. Same
family as the parent ticket
[[bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing]]:
**the output is plausible and specific, and it is about something other than
what happened.** A specific claim is harder to doubt than a vague one, which is
why enumerating the suite names makes this worse rather than better.

It is also the environment rule again — a row whose verdict depends on the
environment can only gate the environment — except here the row does not even
report which environment it ran in.

## Repro

```
$ test -d external/synapse ; echo $?      # 1 — absent
$ make lib-test
...
SKIP lib_synapse + lib_synapse_transitive_unit -- external/synapse absent
...
lib-test ok (… + synapse-ssl) against stable v390
$ echo $?
0
```

## Recommendation

Make the summary report what ran. The smallest honest version keeps the
existing string for the unconditional suites and appends the conditional ones
only inside the `else` arm, e.g. a `LIBTEST_EXTRA` variable set under the
`ifeq`/`else`, interpolated into the final `echo`. The skip branch then yields
`lib-test ok (…) [skipped: synapse] against stable v390`, so the *last* line
carries the caveat rather than relying on a reader scrolling back 750 lines.

The alternative — dropping the enumeration entirely — is worse: the list is
genuinely useful when it is true.

Not applied: the fix is a judgement call about the summary's contract (does
`ok` mean "everything named passed" or "everything attempted passed"), and the
same pattern likely exists in the other conditional guards in this rule. Worth
one sweep rather than one patch — grep the rule for `ifeq`/`SKIP` and check
each against the closing echo.

## 2026-08-29 — FIXED (frankB). It was never one guard; it was 39.

Contract settled by the coordinator, and both readings agreed so there was no
real fork: **`ok` means everything ATTEMPTED passed, and the line must name what
was skipped.**

### The sweep found far more than the ticket described

The ticket names the synapse guard. The rule has **39 SKIP sites**, in three
kinds:

| kind | count | what it did before |
| --- | --- | --- |
| `echo "… SKIP …"` inside a conditional branch | 36 | announced loudly, 700+ lines above the summary |
| `grep -qE '^IPV6 (OK\|SKIP)'` and its `NET6` / `ASYNCNET6` siblings | 3 | **passed in total silence** — a SKIP was accepted as a pass and nothing said so |

The three silent ones are the worse half and the ticket did not know about them.
A host without `AF_INET6` produced a green in which `ipv6`, `net6` and
`asyncnet6` were named as having run, with **no SKIP line anywhere in the log**
to contradict it. `grep -q` also discarded the program's output, so on genuine
failure `job_reason()` got the previous recipe line — the parent defect again,
inside the guard meant to tolerate a missing feature.

### An accumulator, not a re-derivation

Each SKIP branch appends its own name to `$(TESTTMP)/lib-test.skipped`, cleared
at the top of the rule; the summary reads it. The tempting alternative — re-test
the preconditions in the summary and name what is absent — is **one edit instead
of 39 and is wrong**: it duplicates every guard predicate, so the summary and the
guard drift apart the first time either changes. That is the same defect as
`IRNodeOwnsManagedStr` being hand-copied into fifteen emitters, and this repo has
now been bitten by it at both ends of one matrix. The branch that skips is the
only thing that knows it skipped.

Dedup is `awk '!a[$0]++'`, deliberately not `sort -u` — which merges distinct
identifiers under some locales, a hazard already recorded in this repo.

The three silent guards keep their verdict exactly (`OK` and `SKIP` both pass —
the host may genuinely lack `AF_INET6`) and gain two things: the SKIP is recorded
and echoed, and a *failure* now prints the offending line instead of nothing.

### Result

```
lib-test ok (… + reportlab-diff + synapse-ssl) against stable v390 \
  -- SKIPPED: synapse-ssl cstring_batch cwctype (green here does NOT cover them)
```

Wording follows what tstate already does — `seven` prints `coverage — N job(s)
SKIPPED …: green here does not cover them`. **The Makefile summary is being held
to a standard the tooling already meets**, not to a new one, which is a stronger
argument than this ticket originally made.

### Verified without running the suite

`make lib-test` could not be used: it was SIGTERMed on 3 of 5 attempts today from
outside the build, cause unknown and both candidate mechanisms falsified
(`bug-t`/harness, reported separately). So each piece was exercised in scratch
makefiles with the identical recipe text:

- summary with **no file**, an **empty file**, and **duplicates** → clean line,
  clean line, deduped list in encounter order;
- a skip branch appending while a sibling runs → only the skipped name appears,
  exit 0 preserved;
- all three arms of the rewritten `OK`/`SKIP`/other case → OK silent and
  passing, SKIP announced + recorded + passing, other prints
  `FAIL: lib_ipv6 last line was: …` and aborts.

`make` parses the file and the self-host fixedpoint builds.

### Known limitation, not introduced here

`$(TESTTMP)` defaults to `/tmp`, shared by every checkout
([[bug-a-testtmp-defaults-to-a-path-every-checkout-shares]]), so the accumulator
inherits that: two concurrent `lib-test` runs would cross-contaminate the skip
list. The `rm -f` at the top of the rule clears a stale file, so the exposure is
overlap only, and it is exactly the scope of that ticket. Deliberately not
folded in — a change to where every test writes does not belong in this diff.

## Log
- 2026-08-29 — resolved, commit 7e11ab09e.
