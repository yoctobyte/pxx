---
slug: chore-t-six-orphan-gui-tests-the-blanket-was-hiding
title: "Six GUI test files that nothing runs, revealed once check_test_wiring stopped blanketing test/gui"
track: B
type: chore
prio: 30
status: done
found: 2026-08-29
found-by: pxx-a5 (Track T)
owner: pxx-b
---

# The six the blanket was hiding

[[bug-t-check-test-wiring-credits-a-directory-that-a-truncated-token-named]]
fixed the checker; this is its output. Filed separately on purpose — fixing the
instrument was bounded and paid immediately, wiring an unknown tail is
open-ended work of unknown value, and bundling them would have turned a
one-ticket chore into a campaign.

```
gui/test_gtk_signals.pas       gui/test_pcl_showmessage.pas
gui/test_gtk_window.pas        gui/test_pcl_window.pas
gui/test_pcl_helloworld.pas    gui/helloworld/main.pas
```

(Paths given relative to `test/`, deliberately. Spelling them in full inside a
tracked file under `tools/` would credit them and shrink the very report this
ticket is the output of — it happened once already, see the CORRECTION in
[[bug-t-check-test-wiring-credits-a-directory-that-a-truncated-token-named]].
A ticket under `devdocs/` is not scanned, so this is belt-and-braces, but the
habit is the point.)

`grep -rl <stem> Makefile tools/` returns nothing for any of them.
`tools/gui_suite.sh` runs eleven of the seventeen `.pas` subjects under
`test/gui/` and these are not among them.

## Track B, not T

The files are `lib/pcl` widget tests — Track B's file-lane, built with
`$(PXX_STABLE)` and gated by `make lib-test`/`demos`. Track T found them and owns
the checker; it does not own the tests. Same split as everywhere: **T owns the
tool, never the subject.**

## What has to be decided per file, and it is not "wire them"

These are **GUI** tests. `gui_suite.sh` is not part of `make test` — it needs a
display, and that is why it enumerates its cases by hand instead of globbing.
So the disposition for each of the six is one of:

1. **add to `gui_suite.sh`'s case list** — if it is a real case that was simply
   never added (`run_gui_test test_pcl_window` is a one-line change);
2. **exempt in `test/UNWIRED.txt` with a reason** — if it is a manual probe, or
   a Lazarus project's unit rather than a test subject. `helloworld/main.pas` is
   almost certainly this: it is the unit of `helloworld.lpr`, an example
   project, and "nothing runs it" may be the correct end state;
3. **delete** — but only after asking what it is the only executable description
   of. `test_gtk_window` and `test_gtk_signals` are the raw-GTK-FFI pair beneath
   the PCL widgets; if PCL's own tests do not cover the signal-connect path,
   deleting them removes the only place it is written down.

Do not batch-wire them. Four of the six have `.lfm` or window-lifecycle content
that a headless runner cannot assert, and a rule that compiles-but-cannot-run is
the same invisible work one level along.

## The cost side, which is the part worth keeping

frank-b found two of these by hand during the PCL header migration and made the
argument better than a ticket normally can: both were **converted** off the
curated GTK3 header — read, edited, kept consistent with a binding change.
Maintenance paid in full on files that cannot report anything.

The existing framing for an unwired test is "it does not catch its bug". These
are the other half: **an unwired test still bills you for upkeep**, and that
half is the one that keeps being paid without anyone deciding to.

## Log
- 2026-08-30 — resolved, commit c8c469b51.
