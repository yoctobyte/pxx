# MicroPython's `gc`, as nearly every MicroPython script calls it:
# `import gc; gc.collect(); print(gc.mem_free())`. Until 2026-09-27 `import gc`
# did not compile anywhere (no unit, no mimic_gc). lib/rtl/mimic_gc.pas: collect()
# returns 0 -- reference counting has already freed acyclic garbage, and a
# CYCLE IS NOT COLLECTED; mem_free()/mem_alloc() are the pxx heap on the host
# and IDF's heap on ESP32 (the Makefile row builds this file for the C3 and S3);
# enable/disable/isenabled/threshold are accepted and change nothing.
#
# The loop is the check a MicroPython script makes: after warm-up, mem_alloc
# and mem_free stay LEVEL over N passes that build and drop garbage. The first
# run of it found a real leak -- `str(j) * 10` leaked its str(j) temporary, one
# string per evaluation -- so the loop keeps that expression.
# The baseline is taken at pass 120, after `"%d" % i` has reached three digits:
# taken at pass 20 it read 8 bytes high at N = 300, 600 and 2000 alike -- a
# one-time step, not growth. MicroPython-only calls (threshold) mean the
# expected output is not CPython's; CPython has no gc.threshold.
# `keep` is the positive control: it holds every pass's garbage, and the level
# check must then fail.
import gc
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else "check"
gc.enable()
gc.threshold(4096)
print("isenabled", gc.isenabled(), "threshold", gc.threshold(), "collect", gc.collect())
kept = []
free0 = 0
alloc0 = 0
for i in range(300):
    buf = [str(j) * 10 for j in range(50)]
    d = {"k": buf, "n": i, "s": ("%d" % i) * 3}
    if mode == "keep":
        kept.append(d)
    buf = None
    d = None
    gc.collect()
    if i == 120:
        free0 = gc.mem_free()
        alloc0 = gc.mem_alloc()
print("alloc level", gc.mem_alloc() - alloc0 == 0, "free level", gc.mem_free() - free0 == 0)
print("figures", gc.mem_free() >= 0, gc.mem_alloc() > 0)
gc.disable()
