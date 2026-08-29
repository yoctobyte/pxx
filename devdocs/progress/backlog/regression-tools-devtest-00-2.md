---
track: N
prio: 70
---

# regression: tools-devtest#00 red at 8787cfe4235a — a new hardcoded /tmp path in a NilPy test

- **Type:** regression. **Triaged 2026-08-27 by Track T (face 2).**
  Auto-filed by the twatch watcher, host plexus; originally filed with **no
  `track:` line**, which parks a stub in Track T's queue by default. It is not
  Track T's. Re-laned to **N**.
- **Found:** 2026-08-27T15:14:29Z
- **Failing guard:** `tools/testmgr_hardcoded_tmp_devtest.py`
- **Culprit:** `f3422cd14` — *fix(nilpy): a main-program class must not be
  visible inside a unit* (2026-08-27 15:03:58 +0200), 11 minutes before the red.
  It is inside the watcher's own bisect range (`62a4242203a3..8787cfe4235a`),
  the oldest code-bearing commit in it.

## What is actually wrong

`f3422cd14` added `test/test_nilpy_class_named_like_an_rtl_record.npy`, which
hardcodes one `/tmp` path and opens it three times:

```
test/test_nilpy_class_named_like_an_rtl_record.npy:51  f = open("/tmp/pxx_nilpy_rtlrec_probe.txt", "w")
test/test_nilpy_class_named_like_an_rtl_record.npy:56  g = open("/tmp/pxx_nilpy_rtlrec_probe.txt", "r")
test/test_nilpy_class_named_like_an_rtl_record.npy:63  os.remove("/tmp/pxx_nilpy_rtlrec_probe.txt")
```

The path is written by the compiled test **at runtime**, so no Makefile sweep
reaches it and testmgr cannot privatize it either — testmgr rewrites the recipe
text it executes, not string constants inside a binary it runs. Two concurrent
runs therefore share the file, even under testmgr.

**The tool is behaving correctly and there is no Track T defect here.**
`testmgr_hardcoded_tmp_devtest.py` is a RATCHET: it carries a `KNOWN` set of
pre-existing offenders and fails only on a *new* one. It caught exactly what it
exists to catch, 11 minutes after the path landed.

## Fix

Read the directory from the environment, which the sweep already exports;
defaulting to `/tmp` keeps the output byte-identical:

```python
d = os.environ.get("TESTTMP", "/tmp")        # os.environ works in NilPy —
                                             # see test/test_nilpy_environ.npy
f = open(d + "/pxx_nilpy_rtlrec_probe.txt", "w")
```

The file already imports `os` (it calls `os.remove` at line 63), so nothing new
is needed. Adding the path to the guard's `ALLOWED_PATHS` is the *wrong* exit
here — that set is for paths the Makefile also names, where recipe and source
must agree by construction. This one is named only by the source.

## Why prio 70 and not 35

[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]] holds the ~60-path
backlog at prio 35, and that stays where it is. This is a different item: a red
ratchet is a DISABLED ratchet. While `tools-devtest#00` is red on this path,
the next new hardcoded `/tmp` path lands invisibly — the job is already failing,
so it cannot report a second violation as news. The cost of leaving it is not
one shared temp file; it is the guard.

## Repro

```
python3 tools/testmgr_hardcoded_tmp_devtest.py     # ~1s, no build needed
```

Reproduced at `d865d8cad` (2026-08-27, Track T session): 78 guards green, this
one red, same single path. The stub's original repro line ran the whole
`tools-devtest` batch under testmgr for what the guard answers on its own in a
second — prefer the line above.

*Enriched from a watcher stub by Track T (face 2), which owns the tool and not
the bug — the fix belongs to the lane that owns the test source.*

## Extra cost: this red also fails PIN VERIFICATION

Noticed while confirming the v389 retarget. The watcher's `pin_verify` block
records this job red **at the pinned tree**, not only at HEAD:

```
ver v388  sha 20664a1576d3  tier full  verdict RED
red: test-emit-obj#src:test/cxtensa_obj.c@1, tools-devtest#00
```

So the one-line temp-path fix clears a red from *two* places: the HEAD ladder
and every pin verification that runs while it stands. A pin-verify red is the
more expensive of the two — it is the binary every other track is building
with right now, so a red there is what an agent checking "is my ground sound?"
sees first, and a known-benign entry sitting in that list is exactly the noise
that teaches people to skim it.

Both entries in that list are already ticketed and neither is a compiler
defect: this one, and [[regression-test-emit-obj-cxtensa-obj]].
