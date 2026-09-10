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
summary: "MEASURED 2026-09-10 at 546d4dcbd305: `tools/busybox_diff.sh --applets cat --targets x86_64` dies before building the pxx subject at all, on `the banner normaliser matched nothing`. It is not a banner-format change and it is not a tree problem -- at one applet the transcript legitimately contains NO banner, so the control at :1578 cannot fire by construction. run_cases (:1227) branches on NAPPLETS == 1 and runs ONLY run_cat_cases, whose 12 cases are all `cat <files>` plus a stdin case; the banner comes from run_dispatch_cases (`--help`, bare busybox), which that branch skips. The normaliser and its control were added 3e77e3f1f (2026-09-01) for the UPSTREAM cross-check, inside `if [ -n \"$UPSTREAM\" ]`, and configure_tree builds $BB/busybox itself, so UPSTREAM is always found and the block always runs. Confirmed two ways that fail differently: the live run (0 `BusyBox` lines in oracle_gcc.out over 72 lines) and the code path. Rung 1 is the script's own stated success criterion (:7) and it has been unrunnable for nine days -- unnoticed because the recent busybox work is all at 2 to 394 applets, where the banner IS printed and the control is correct. THE COST IS THE MESSAGE, not just the exit: `either the banner format changed or these transcripts never print it` sends a reader after a busybox or harness regression that does not exist. The control is right to exist and is simply mis-scoped: assert it only where a banner is expected (NAPPLETS > 1), and for the one-applet transcript either skip the normalisation or make its absence the asserted fact. Do NOT weaken it to `grep -q || true` -- that is the silent no-op it was written to prevent."
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
