---
prio: 30
track: B
type: bug
blocked-by: []
summary: "tools/gui_shot.sh rejects a capture as blank when it is <= BLANK_MAX=4000 bytes, on a comment claiming 'a blank frame is ~1-3 KB'. Measured 2026-08-30 at the script's own default 1100x700 under ffmpeg 8.0.1: a fully blank frame is 4013 bytes, five samples, no variance. 4013 > 4000, so the blank check passes every blank capture and the Xvfb restart-and-retry path it guards can never fire. The number was right when written; the encoder or the default size moved under it. Lane note: gui_shot.sh is not in Track T's listed file set, so this is filed to the lane that uses it for PCL/GUI work — reroute if that reading is wrong."
status: done
owner: frankB
---

# `gui_shot.sh`'s blank-frame detector no longer detects a blank frame

- **Type:** bug (stale measured constant in agent tooling) — filed 2026-08-30 by
  the Track T agent, from the stale-constant sweep in `track-t.md`
  ("which numbers in your reports have NEVER changed?"). One of exactly two
  values in `tools/**`/`test/**` that the sweep classified as an *asserted
  observation* rather than a tunable — and it had in fact rotted.

## Measured

`tools/gui_shot.sh:118`:

```sh
# A real PCL window compresses to well over this; a blank frame is ~1-3 KB.
BLANK_MAX=4000
```

At the script's own default `GUI_SHOT_SIZE=1100x700`, on ffmpeg 8.0.1-3ubuntu2,
a capture of an empty Xvfb display is:

```
4013 4013 4013 4013 4013     (five samples, no variance)
```

The test is `[ "${SZ:-0}" -le "$BLANK_MAX" ]`. **4013 > 4000, so a completely
blank frame is accepted as a real window.** The margin is 13 bytes and the
number is deterministic, so this is not an intermittent edge — it fails every
time, in one direction.

For scale, the same empty display at 1024x768 measures 4192 bytes. The comment's
"~1-3 KB" is no longer true at any size the script uses; the encoder or the
default resolution moved under a number that was correct when it was written.

## Why it matters more than a missed warning

The threshold guards two things, and both are now dead:

1. the `gui_shot: capture looks blank` error, which is how a caller learns the
   screenshot is worthless;
2. the **restart-and-retry** path — on a suspected-blank first grab the script
   restarts Xvfb, waits longer and re-grabs, which is the recovery for a wedged
   display. That branch is now unreachable, so a genuinely wedged display is
   never recovered and is reported as success.

Mitigating: a human or agent usually *looks* at the resulting PNG, so a blank
image is not invisible the way a wrong number is. This is tooling with a reader
in the loop, not a silent gate — hence prio 30 rather than higher.

## Fix

Re-derive the threshold rather than nudging it: measure an empty frame at the
default size on the current toolchain and set the bound with real headroom, or
stop using compressed size as the proxy at all (a uniform frame is better
detected by sampling pixels than by guessing at PNG entropy — that is what makes
the constant resolution- and encoder-dependent in the first place).

Whatever is chosen, **record how it was derived next to the value**, because the
current comment is exactly the failure: a measurement asserted once, in prose,
with nothing that re-checks it.

## Lane

`tools/gui_shot.sh` is not in Track T's listed file set (`testmgr.py`,
`twatch.py`, `tstate/**`, the fuzzers), so T filed rather than fixed it. Routed
to **B** because the script exists to screenshot PCL/GUI apps and
`test/gui/test_pcl_stream_paned.pas` is written to cooperate with it. If it is
better read as shared agent tooling, reroute — the finding does not depend on
the answer.

## Acceptance

A blank capture at the default size is reported blank, and the retry path is
reachable again. The value carries a note saying how and when it was measured.

## Resolved 2026-08-30 (frankB) — and the ticket's first fix option turns out to be impossible

Reproduced exactly as filed, on ffmpeg 8.0.1-3ubuntu2 at the default 1100x700:
an empty Xvfb capture is **4013 bytes**, five samples, no variance. `4013 > 4000`,
so `[ "$SZ" -le "$BLANK_MAX" ]` is false and every blank frame is accepted.
Confirmed end to end by running the **pre-change script** on a command that draws
nothing — it exits **0** and prints `gui_shot: ... (4013B)` as if it had captured
a window.

### The measurement that changed the fix

The ticket offered two options: re-derive the threshold with real headroom, or
stop using compressed size as the proxy. **The first is not available.** Measured
on the same display, same size, same encoder:

```
empty display        4013 bytes
real xterm window    4068 bytes
```

**Fifty-five bytes apart.** The size proxy has not merely drifted out of
calibration — it has no discriminating power left at any threshold. That is not
an accident of this encoder either: a mostly-empty frame compresses to nearly the
same size whether or not something is drawn in one corner, because the entropy of
the drawn region is tiny next to the uniform background it sits on. Bumping the
constant would have produced a number with a 55-byte window that fails in both
directions, and it would have started rotting immediately, being both resolution-
and encoder-dependent by construction.

So this is the overhaul, not the microfix — and it is the smaller change, because
it deletes the dependence on resolution and encoder rather than re-tuning it.

### What replaced it

The share of pixels differing from the frame's most common luma, in units of
1/10000, computed from decoded pixels (`scale=256:256:flags=neighbor,format=gray`
→ `od` → histogram). A **ratio**, so it does not move with resolution; **decoded
pixels**, so it does not move with the encoder. Same two frames:

```
empty display          1 /10000   (0.012% — the mouse cursor, ~60 px of 770000)
real xterm window   1983 /10000   (19.8%)
```

Three orders of magnitude apart. `BLANK_BP=50` (0.5%) sits 40x above the cursor
noise floor and well below a small dialog — a 200x100 window on this canvas is
~260/10000, still 5x over the line.

**A blank display is not uniform**, which is worth recording because it defeated
the first thing I tried. Counting *distinct* luma values looked cleaner and gave
`blank = 1, content = 2+` on a 64x64 grid — but only because that grid happened
to miss the cursor. At 128x128 the same blank frame gives 2 distinct values and
the test collapses. The fraction is robust to a cursor in a way a distinct-count
is not, and the cursor is always there.

### Verification — both arms, status taken from the script itself

```
real window (xterm):  exit 0   "(4068B, 1982/10000 non-uniform)"
draws nothing:        exit 1   "capture looks blank (1/10000 non-uniform, 4013B)"
pre-change script,
  same blank case:    exit 0   <- the bug, demonstrated rather than asserted
```

The retry path is reachable again: on the blank arm the Xvfb restart visibly
fires before the second grab. No caller parses the output format — every
reference to `gui_shot.sh` outside the script is documentation or a usage
example — so widening the success line to carry the ratio breaks nothing.

The PCL app the script exists to shoot could **not** be used as the live subject
here: `test/gui/test_pcl_helloworld.pas` refuses to build on this box because
`<gtk/gtk.h>` resolves to GTK2 (see [[decide-does-the-legacy-gtk-alias-still-point-at-gtk-2]]).
`xterm` stands in — a real X client drawing a real window, which is exactly the
discrimination under test. Worth re-confirming against a PCL window on a box with
GTK3 headers; the numbers are three orders of magnitude apart, so the conclusion
is not delicate, but the subject was a substitute and should be named as one.

### Acceptance

- blank capture at the default size is reported blank — **yes**, exit 1;
- retry path reachable again — **yes**, observed firing;
- the value carries a note saying how and when it was derived — **yes**, both
  measurements and their toolchain are recorded in the script beside the
  constant, together with the instruction to re-measure and re-record on change.
  The old comment asserted a measurement once, in prose, with nothing that
  re-checked it, which is exactly how it rotted.

### One thing left for Track T

`devdocs/dev/track-t.md` (lines ~390 and ~405) names `BLANK_MAX=4000` as one of
its two "asserted observations" and records it as rotted. That record is still
historically accurate, but the constant no longer exists. Left untouched — it is
Track T's file, and the sweep record is theirs to update.

## Log
- 2026-08-30 — resolved, commit a13e52b21.
