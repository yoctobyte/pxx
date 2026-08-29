---
track: A+T
prio: 45
type: bug
blocked-by: []
summary: "lib-test's closing `lib-test ok (... + synapse-ssl ...)` line enumerates suites unconditionally, including ones an `ifeq ($(wildcard external/synapse),)` guard skipped. Measured 2026-08-29 in a tree with no external/synapse: the recipe printed `SKIP lib_synapse ...` at log line 441 and then `lib-test ok (... + synapse-ssl)` at line 1197. The skip is loud, but it is 750 lines above the summary; the summary is the LAST line, which is what a human reads and what job_reason() records as the tail. A green claiming a component that did not run."
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
