---
prio: 30
track: B
type: bug
blocked-by: []
summary: "tools/gui_shot.sh rejects a capture as blank when it is <= BLANK_MAX=4000 bytes, on a comment claiming 'a blank frame is ~1-3 KB'. Measured 2026-08-30 at the script's own default 1100x700 under ffmpeg 8.0.1: a fully blank frame is 4013 bytes, five samples, no variance. 4013 > 4000, so the blank check passes every blank capture and the Xvfb restart-and-retry path it guards can never fire. The number was right when written; the encoder or the default size moved under it. Lane note: gui_shot.sh is not in Track T's listed file set, so this is filed to the lane that uses it for PCL/GUI work — reroute if that reading is wrong."
status: working
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
