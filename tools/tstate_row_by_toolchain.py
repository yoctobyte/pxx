#!/usr/bin/env python3
"""Cross-tab a tstate ROW's verdict against the EMULATOR/toolchain version.

  tools/tstate_row_by_toolchain.py <row-substring> [ISO-birth-date]

WHY THIS EXISTS. A tstate verdict is a statement about a qemu and a gcc as much
as about a tree, and until a reader splits on `toolchain:` a host looks like the
variable. It is not: a host is a proxy for its toolchain only until someone runs
`apt`. Measured 2026-09-22 with this script on `c_crtl_wait` -- 8.2.2 gave 541
red / 4 ok where 10.2.1 gave 0 red / 361 ok, from byte-identical compiler bytes.

POPULATION, stated because a bare count is not re-derivable: every file in
devdocs/progress/tstate/reports/*.md at the tree recorded below, restricted to
(a) tier in {native, full} -- the only tiers that run test-core -- and (b) date
>= 2026-09-04T16:54:32Z, the test's one and only commit. Before that instant the
row did not exist, so its absence from a report is not a pass; that pre-birth
bucket is what made my earlier 230s+ analysis rest on n=0.

WHY THIS VARIABLE AND NOT WALL TIME. tools/twatch.py's own comment, written
2026-09-04, records that this row was "red on one and green on the other from
BYTE-IDENTICAL compiler bytes" across qemu 8.2.2 and 10.2.1 -- and the
toolchain: field exists BECAUSE of this row. The variable was recorded in the
archive before I started looking for it.

A report lists only its reds, so for a report that ran the row, absence == pass.
That inference is the one soft step here and it is stated rather than hidden.
"""
import glob, os, re, subprocess, collections, sys

ROW = sys.argv[1] if len(sys.argv) > 1 else "c_crtl_wait"
# A row that did not exist yet is ABSENT from a report, not passing. Pass the
# row's creating commit date or its absence silently inflates the ok column --
# that mistake cost an evening and is why this argument is not optional in
# spirit. `git log --diff-filter=A --format=%aI -- <path>` gives it.
BIRTH = sys.argv[2] if len(sys.argv) > 2 else "2026-09-04T16:54:32Z"

sha = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                     text=True).stdout.strip()

files = sorted(glob.glob("devdocs/progress/tstate/reports/*.md"))
tab = collections.defaultdict(lambda: [0, 0])   # key -> [red, ok]
byhost = collections.defaultdict(lambda: [0, 0])
skipped_tier = 0
skipped_early = 0
nofield = 0
firstred = {}

for f in files:
    txt = open(f, encoding="utf-8", errors="replace").read()
    head = txt.split("\n## ", 1)[0]

    def field(name):
        m = re.search(r"^%s:\s*(.*)$" % name, head, re.M)
        return m.group(1).strip() if m else None

    tier = field("tier")
    if tier not in ("native", "full"):
        skipped_tier += 1
        continue
    date = field("date") or ""
    if date < BIRTH:
        skipped_early += 1
        continue
    tc = field("toolchain")
    if not tc:
        nofield += 1
        continue
    mq = re.search(r"qemu=([0-9.]+)", tc)
    mg = re.search(r"gcc=([0-9.]+)", tc)
    qemu = mq.group(1) if mq else "none"
    gcc = mg.group(1) if mg else "none"
    host = field("host") or os.path.basename(f).rsplit("-", 1)[-1][:-3]

    # WHICH SECTIONS MEAN RED -- and this list is ASSERTED, not assumed.
    #
    # THE SAME MISTAKE HAS NOW BEEN MADE THREE TIMES ON THIS ARCHIVE, each time
    # by guessing the spellings instead of enumerating them: first counting
    # STILL-RED and dropping NEW-RED (which moved 14 rows to 33 and 94 to 129),
    # then this script scoring four reports as PASSES because their heading is
    # `## RED -- no baseline at this sha, ...`, a third spelling that exists in
    # exactly four files archive-wide. A `## FIXED` section names rows that went
    # GREEN, so a matcher loose enough to catch every red would invert those.
    #
    # So the section vocabulary is closed and any NEW heading aborts. A silent
    # miscount is the failure mode here; a crash is the cheap one. Enumerate
    # with:  grep -h '^## ' devdocs/progress/tstate/reports/*.md
    RED_SECS = ("STILL-RED", "NEW-RED", "RED")
    OTHER_SECS = ("FIXED", "first failure", "failure detail")
    redsec = []
    for seg in re.split(r"^## ", txt, flags=re.M)[1:]:
        if seg.startswith(RED_SECS):
            redsec.append(seg)
        elif not seg.startswith(OTHER_SECS):
            raise SystemExit(
                "%s: UNKNOWN report section %r -- refusing to count.\n"
                "A section this script does not classify is a silent miscount "
                "waiting to happen; add it to RED_SECS or OTHER_SECS."
                % (f, seg.split("\n", 1)[0][:70]))
    red = ROW in "\n".join(redsec)

    key = (qemu, gcc)
    tab[key][0 if red else 1] += 1
    byhost[(host, qemu)][0 if red else 1] += 1
    if red:
        firstred.setdefault((host, qemu), date)

print("row: %s" % ROW)
print("tree: %s" % sha)
print("population: tstate reports, tier in {native,full}, date >= %s" % BIRTH)
print("  files total %d | skipped other-tier %d | skipped pre-birth %d | no toolchain field %d"
      % (len(files), skipped_tier, skipped_early, nofield))
print()
print("BY EMULATOR (the variable twatch.py named on 2026-09-04)")
print("  %-10s %-8s %6s %6s %8s" % ("qemu", "gcc", "RED", "ok", "red%"))
for (q, g), (r, o) in sorted(tab.items()):
    n = r + o
    print("  %-10s %-8s %6d %6d %7.1f%%" % (q, g, r, o, 100.0 * r / n if n else 0))
print()
print("BY (HOST, EMULATOR) — the population unit, because a verdict is about both")
print("  %-10s %-8s %6s %6s %8s  %s" % ("host", "qemu", "RED", "ok", "red%", "first red"))
for (h, q), (r, o) in sorted(byhost.items()):
    n = r + o
    print("  %-10s %-8s %6d %6d %7.1f%%  %s"
          % (h, q, r, o, 100.0 * r / n if n else 0, firstred.get((h, q), "-")))
