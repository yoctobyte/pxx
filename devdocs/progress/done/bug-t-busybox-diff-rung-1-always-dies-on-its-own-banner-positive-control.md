---
slug: bug-t-busybox-diff-rung-1-always-dies-on-its-own-banner-positive-control
title: "busybox_diff.sh --applets cat cannot complete: its banner positive control can never fire at one applet"
track: C
prio: 55
type: bug
blocked-by: []
status: new
created: 2026-09-10
found: 2026-09-10
found-by: frank-user
owner: ""
summary: "RESOLVED 2026-09-16: the banner positive control was drawn from the wrong population — at ONE applet run_cases never calls run_dispatch_cases, so the transcript legitimately has no banner and the assert could not fire by construction, killing rung 1 (the script's own success criterion) for nine days. Scoped to NAPPLETS > 1, with the one-applet arm asserting the COMPLEMENT (there must be NO banner) rather than being weakened to `|| true`. Both arms driven with synthetic transcripts to prove each can FAIL. Rung 1 now runs and is GREEN: byte-identical to the gcc oracle over 12 cases."
---

# Rung 1 dies on a control that cannot fire at one applet

## Repro

```
$ tools/busybox_diff.sh --applets cat --targets x86_64 --keep
busybox-diff: applets=cat  translation units=25
  ORACLE  gcc unity build (12 cases)
busybox-diff: the banner normaliser matched nothing -- either the banner
  format changed or these transcripts never print it, and in both cases this
  comparison is not the one it claims to be
  (rc=1, the pxx subject was never built)
```

## Why, and why it is the second half of its own message

`tools/busybox_diff.sh:1571` normalises the `BusyBox v… multi-call binary.`
banner out of the **upstream** cross-check only, because the banner carries
`AUTOCONF_TIMESTAMP` and busybox does not relink when only that moves
(frankD, 2026-09-01, LOGBOOK:404 — a good finding and a correct fix). It guards
the normalisation with a positive control at :1578, which is exactly right:
a normaliser that silently matched nothing would restore the un-normalised
comparison it replaced.

The control is scoped to the wrong population. `run_cases` at :1227:

```sh
if [ "$NAPPLETS" -eq 1 ]; then
  run_cat_cases "$runner" "$dir/busybox"
  return
fi
run_dispatch_cases "$runner" "$dir"
...
```

`run_cat_cases` (:838) is 12 `cat`-with-files cases plus one stdin case. **None
of them prints a banner** — the banner comes from `run_dispatch_cases` (:855),
which runs `--help` per applet, `busybox --list`, `busybox --help` and bare
`busybox`, and which the one-applet branch returns before reaching.

So at one applet there is nothing to normalise, and the control reads that as
the failure it was written to catch. Its own message names the true cause as the
second of two possibilities — *"or these transcripts never print it"* — and a
reader hitting it will chase the first.

Measured on the live transcript: `oracle_gcc.out` is 72 lines and contains
**zero** lines matching `BusyBox`.

## Why it went unnoticed for nine days

Every busybox run since has been at a wider scope, where `NAPPLETS > 1`, the
dispatch cases run, the banner is present and the control is doing real work:
frankZ's 394-applet `--separate` run (8ea912a48, 938 cases byte-identical),
frankD's rung-2 ash work, the 258-applet kiosk. Rung 1 is the cheap smoke test,
so nobody was running the one configuration that breaks.

`--applets cat` is named at :7 as *"the success criterion of"* the kiosk
rung 1.

## The fix, and the shape to avoid

Assert the control **where a banner is expected**: gate it on `NAPPLETS > 1`,
or better, derive the expectation from whether the case set includes a
dispatch case, so the two stay in sync the way frankD's ASH_ON/ASH_OFF list
does for the ash config.

For the one-applet transcript, the honest statement is the opposite assertion —
*this transcript contains no banner, so nothing is normalised here* — which is
a control too, and a cheaper one.

**Do not** relax it to `grep -q … || true`. Per CLAUDE.md, a guard that cannot
fail is not a guard; the same sentence forbids a guard that cannot pass. Both
halves apply here and the remedy is scope, not strength.

## Note on my own measurement

I copied a busybox tree from another checkout into
`library_candidates/busybox` to run this, which is a contamination risk worth
naming. It does not reach this finding: `configure_tree` reconfigures and
rebuilds the tree (the `$BB/busybox` it compares against is stamped during the
run), and the cause is a branch in `run_cases` that no tree state can change.

## RESOLVED 2026-09-16 (frankb-56)

**Reproduced at HEAD first, not taken from the 2026-09-10 reading** — a claim
about an instrument decays like a lock, silently, in the direction of doing
nothing. It still dies, identically:

```
busybox-diff: the banner normaliser matched nothing -- either the banner format
  changed or these transcripts never print it, ...
```

and the transcript now has **76 lines and 0 matching `^BusyBox`** (72 when
filed — the tree moved, the conclusion did not).

### The fix: scope it to the population that has a banner, and assert BOTH ways

The control was right to exist and was drawn from the wrong population. At one
applet `run_cases` takes the `run_cat_cases` branch and never calls
`run_dispatch_cases` — the only thing that runs `--help` or the bare multi-call
binary — so the transcript legitimately contains no banner and the assert could
not fire by construction.

**Not weakened to `|| true`**, which is the silent no-op it was written to
prevent. The one-applet arm asserts the **complement**: there must be NO banner.
A banner appearing there means `run_cases` changed shape and the normaliser is
silently in play on a comparison nobody scoped it for — which is the same class
of defect the original control was guarding against, seen from the other side.

### Both arms proved able to FAIL, which is the thing this ticket is about

A guard that cannot fail is not a guard, so the new one was driven with
synthetic transcripts rather than trusted:

| arm | transcript | expected | got |
| --- | --- | --- | --- |
| one applet | no banner | PASS | PASS |
| one applet | a banner | **FAIL** | FAIL |
| multi applet | normalised banner | PASS | PASS |
| multi applet | un-normalised banner | **FAIL** | FAIL |
| multi applet | no banner at all | **FAIL** | FAIL |

### Rung 1 now runs, and it is GREEN

```
busybox-diff: applets=cat  translation units=25
  ORACLE  gcc unity build (12 cases)
  ORACLE  busybox agrees with the gcc build
  PASS    x86_64   byte-identical to the gcc oracle over 12 cases
busybox-diff: GREEN
```

The script's own stated success criterion (`:7`) had been unrunnable for nine
days, and the result behind it was a pass the whole time. The multi-applet arm was re-run with real data as well, since that is the
population the original control was written for and the one this change must not
disturb — `--applets "cat echo"`, 28 translation units, **GREEN, byte-identical
to the gcc oracle over 29 cases**. That arm PASSING is itself the evidence that
the normaliser still fires there: the assert is what it has to get past.

### Method note

`sh -n` reported a syntax error at line 538 on this file — and on the pristine
HEAD copy too. The script is `#!/usr/bin/env bash` and uses process
substitution; `sh -n` was the wrong checker, not the file the wrong shape. The
instrument answered correctly about a different shell. `bash -n` is clean on
both.
