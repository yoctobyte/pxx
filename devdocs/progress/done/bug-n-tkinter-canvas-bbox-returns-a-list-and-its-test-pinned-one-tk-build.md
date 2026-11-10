---
slug: bug-n-tkinter-canvas-bbox-returns-a-list-and-its-test-pinned-one-tk-build
track: N
type: bug
prio: 40
status: done
owner: ""
created: 2026-11-10
found-by: claude (rerunning auto-filed regression tickets at HEAD)
blocked-by: []
summary: "lib-test#00 was RED on plexus at 5f11a77638: examples/tk/callbacks.npy printed `bbox [0, 0, 11, 11]` where the row expected `bbox [1, 1, 10, 10]`. Two defects: Canvas.bbox built a LIST although CPython returns a tuple (its own declaration comment says so), and the expectation was pinned in July to numbers this host's Tk 8.6.17 does not give -- CPython prints (0, 0, 11, 11) here, because a canvas bbox includes the outline and Tk documents it as possibly a few pixels larger."
---

# tkinter Canvas.bbox returns a list, and its test pinned one Tk build

## Fix

- lib/pcl/tkinter.pas, Canvas.bbox: the TPyList is tagged PYSEQ_TUPLE
  (mimic_struct's unpack does the same), so `print(c.bbox(i))` shows
  `(0, 0, 11, 11)` like python3.
- Makefile lib-test row lib_tk_callbacks: the expectation is CPython running
  the same examples/tk/callbacks.npy under the same xvfb, not a pinned
  printf. Without python3's tkinter the row prints a SKIP and records it in
  lib-test.skipped rather than comparing against nothing.

## Verified

`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'`
GREEN (lib-test#00, 260 s). pxx output and python3's are identical on the six
lines the row compares.
