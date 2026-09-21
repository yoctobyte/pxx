# PC-sampling profiler for pxx-emitted binaries, driven by gdb.
#
#   gdb --batch -x tools/pxx_pc_sample.py --args ./prog arg1 arg2
#
# Environment:
#   PXX_SAMPLES   how many samples to take          (default 100)
#   PXX_SETTLE    seconds before the first sample   (default 0)
#   PXX_INTERVAL  seconds between samples           (default 0.15)
#   PXX_MAP       path to the .map                  (default: <binary>.map)
#   PXX_MAXOFF    offset past which a sample is UNATTRIBUTED  (default 8192)
#   PXX_THREAD    thread to sample                  (default 1)
#   PXX_STALE_MAP set to 1 to override the map-older-than-binary refusal
#
# WHY PC AND NOT A BACKTRACE. A pxx-emitted binary has no symtab, no .debug_*
# and no .eh_frame -- often no section headers at all. gdb can neither
# symbolise nor UNWIND: asking for `bt` yields a column of "?? ()" whose
# addresses are not a call chain. So this samples the PROGRAM COUNTER and
# resolves it against the `.map` sidecar.
#
# WHAT THAT BUYS AND WHAT IT COSTS: a flat SELF-time profile. There is no
# caller information. It answers "what is executing" and CANNOT answer "who
# called it". Say which when you report, because a flat profile read as an
# inclusive one attributes a callee's cost to nobody.
#
# ================= THE THREE WAYS THIS INSTRUMENT LIES ===================
#
# 1. A STALE MAP RESOLVES EVERY ADDRESS AND IS WRONG ABOUT ALL OF THEM.
#    The map is valid only for the exact binary that emitted it, and nothing
#    in it records which. This script REFUSES when the map is older than the
#    binary (`compiler/pascal26-debug.map` was 22 days older than
#    `compiler/pascal26` when this was written -- a live instance, sitting
#    there, that would have produced a confident and entirely fictional
#    profile). Regenerate rather than override: pxx writes one next to every
#    output unless `--no-map` is passed.
#
# 2. NEAREST-PRECEDING-SYMBOL ALWAYS ANSWERS, so it manufactures a plausible
#    name for any address in a gap the map does not describe. Measured
#    2026-09-20: 15 of 100 samples -- the LARGEST bucket -- resolved to
#    `_start`, and were really in unnamed variant retain/release stubs in the
#    2482-byte gap after it. So every bucket below prints the symbol's REGION
#    SIZE, and anything past MAXOFF is reported UNATTRIBUTED rather than
#    credited leftward. A large region is the tell: one binary's map had gaps
#    of 483136 bytes.
#
#    To name a gap, dump the raw bytes -- `objdump -d` prints NOTHING and
#    exits 0 on a sectionless ELF, which is its own silent-zero trap:
#      dd if=<bin> bs=1 skip=$((ADDR-0x400000)) count=256 of=/tmp/c.bin
#      objdump -D -b binary -m i386:x86-64 --adjust-vma=ADDR /tmp/c.bin
#    (the subtrahend is the first PT_LOAD's vaddr; `readelf -l` prints it.)
#
# 3. A SAMPLER THAT COLLECTS NOTHING LOOKS LIKE A PROGRAM THAT DID NOT RUN.
#    Never add `noprint` to the `handle` line: gdb's `noprint` implies
#    `nostop`, so it silently cancels the `stop`. And `interrupt` under
#    `run &` never delivers in gdb batch mode, because a Python sleep blocks
#    gdb's own event loop -- hence the synchronous `continue` below plus an
#    external ticker. Validate against /bin/sleep, which costs no CPU and so
#    does not disturb anyone else measuring on the box.

import bisect, gdb, io, os, re, subprocess, sys
from collections import Counter

N        = int(os.environ.get("PXX_SAMPLES", "100"))
SETTLE   = float(os.environ.get("PXX_SETTLE", "0"))
INTERVAL = float(os.environ.get("PXX_INTERVAL", "0.15"))
MAXOFF   = int(os.environ.get("PXX_MAXOFF", "8192"))
THREAD   = os.environ.get("PXX_THREAD", "1")

gdb.execute("set pagination off"); gdb.execute("set confirm off")
try: gdb.execute("set debuginfod enabled off")
except gdb.error: pass
gdb.execute("set startup-with-shell off")
# `stop` implies `print`. DO NOT ADD `noprint` -- see hazard 3 above.
# PICK A SIGNAL THE SUBJECT DOES NOT USE. Default SIGUSR1, but a program that
# handles it gets its OWN handler invoked by the sampler's ticker -- the
# instrument injecting the phenomenon under test. Measured 2026-09-21: pointing
# this at test_threadsafe_heap_lock_deadlock_diag, whose whole subject is a
# SIGUSR1 handler that allocates, would have driven the very collision the test
# is trying to observe. `nopass` stops delivery to the program, so the handler
# does not actually run -- but the stop still perturbs the timing of a race,
# and a signal the subject installs is the one place that matters.
SIG = os.environ.get("PXX_SIGNAL", "SIGUSR1")
gdb.execute("handle %s stop nopass" % SIG)

binpath = gdb.current_progspace().filename
mappath = os.environ.get("PXX_MAP") or (binpath + ".map" if binpath else "")
if not mappath or not os.path.exists(mappath):
    alt = re.sub(r'\.[^./]*$', '', binpath or "") + ".map"
    if os.path.exists(alt): mappath = alt

addrs, names = [], []
if mappath and os.path.exists(mappath):
    if binpath and os.path.getmtime(mappath) < os.path.getmtime(binpath) \
       and os.environ.get("PXX_STALE_MAP") != "1":
        print("REFUSING: map is OLDER than the binary, so every name it returns is fiction.")
        print("  map    %s  (%s)" % (mappath, os.path.getmtime(mappath)))
        print("  binary %s  (%s)" % (binpath, os.path.getmtime(binpath)))
        print("  Regenerate it (pxx emits one unless --no-map), or set PXX_STALE_MAP=1")
        print("  if you have some other reason to believe it matches.")
        raise SystemExit(2)
    for ln in io.open(mappath, encoding="utf-8", errors="replace"):
        m = re.match(r'^\s*(0x[0-9a-fA-F]+)\s+(\S.*)$', ln)
        if m:
            addrs.append(int(m.group(1), 16)); names.append(m.group(2).strip())
    p = sorted(zip(addrs, names)); addrs = [a for a, _ in p]; names = [n for _, n in p]
else:
    print("NOTE: no map found. Sampling raw PCs only; buckets will be addresses.")

def resolve(pc):
    """-> (name, offset, region_size, confident)"""
    if not addrs: return ("0x%x" % (pc & ~0xfff), 0, 0, False)
    i = bisect.bisect_right(addrs, pc) - 1
    if i < 0: return ("BELOW-MAP", 0, 0, False)
    region = (addrs[i + 1] - addrs[i]) if i + 1 < len(addrs) else 0
    off = pc - addrs[i]
    return (names[i], off, region, off <= MAXOFF)

gdb.execute("starti")   # not `start`: some pxx binaries carry TWO `main` symbols
pid = gdb.selected_inferior().pid
print("pxx_pc_sample: pid=%d N=%d settle=%.2f interval=%.2f maxoff=%d symbols=%d map=%s"
      % (pid, N, SETTLE, INTERVAL, MAXOFF, len(addrs), mappath or "(none)"))

ticker = subprocess.Popen(
    ["sh", "-c", "sleep %f; i=0; while [ $i -lt %d ]; do kill -%s %d 2>/dev/null || exit 0; "
                 "sleep %f; i=$((i+1)); done"
                 % (SETTLE, N + 5, SIG[3:] if SIG.startswith("SIG") else SIG, pid, INTERVAL)])

def pc_now():
    return int(gdb.parse_and_eval("$pc").cast(gdb.lookup_type("unsigned long")))

hits, raw, taken = Counter(), [], 0
try:
    for i in range(N):
        gdb.execute("continue")
        try:
            gdb.execute("thread %s" % THREAD, to_string=True)
        except gdb.error:
            pass                      # single-threaded, or that thread is gone
        try:
            pc = pc_now()
        except gdb.error:
            break
        nm, off, region, ok = resolve(pc)
        hits[nm if ok else "UNATTRIBUTED"] += 1
        raw.append((pc, nm, off, region, ok))
        if i == 0:
            print("SAMPLE0 pc=0x%x -> %s +0x%x (region %d bytes) confident=%s"
                  % (pc, nm, off, region, ok))
            if not ok and addrs:
                print("WARNING: first sample resolves nowhere plausible; check the map matches.")
        taken += 1
except gdb.error as e:
    print("gdb stopped after %d samples: %s" % (taken, e))
finally:
    try: ticker.terminate()
    except Exception: pass

print("\n=== RAW ===")
for k, (pc, nm, off, region, ok) in enumerate(raw):
    print("  %3d  0x%012x  %-38s +0x%-6x region=%-7d %s"
          % (k, pc, nm, off, region, "" if ok else "UNATTRIBUTED"))

print("\n=== FLAT SELF-TIME, %d samples, thread %s ===" % (taken, THREAD))
print("      %     n   region  symbol")
for nm, c in hits.most_common():
    region = next((r for _, n2, _, r, _ in raw if n2 == nm), 0)
    flag = "  <-- region is large; disassemble before believing this name" \
           if region > 65536 else ""
    print("  %5.1f%%  %3d  %7d  %s%s" % (100.0 * c / max(taken, 1), c, region, nm, flag))
print("\ntaken=%d of %d   (flat self-time: what is executing, never who called it)"
      % (taken, N))
