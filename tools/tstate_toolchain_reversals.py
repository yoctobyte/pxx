#!/usr/bin/env python3
"""Every job id's red rate under each toolchain, to find genuine REVERSALS.

WHY. The cross-tab that says c_crtl_wait is 0% red on qemu 10.2.1 and ~100% on
8.2.2 cannot, by itself, distinguish the emulator from the HOST -- host and
toolchain are 1:1 in this window, so both splits are the same split. A row that
leans the OTHER way is what makes the instrument falsifiable. My first candidate
for that (`compiler_srchash`) turned out not to be a row at all: the substring
matches 35 distinct job ids, because tools/compiler_srchash.sh is a SOURCE
PREREQUISITE listed by dozens of unrelated jobs rather than a test.

So this enumerates FULL job ids -- never substrings -- and prints the set, which
is the rule that mistake violated.
"""
import glob, re, collections

BIRTH = "2026-09-04T16:54:32Z"
MIN_N = 30          # per side; below this a rate is noise

red = collections.defaultdict(lambda: collections.Counter())
tot = collections.Counter()

for f in sorted(glob.glob("devdocs/progress/tstate/reports/*.md")):
    txt = open(f, encoding="utf-8", errors="replace").read()
    head = txt.split("\n## ", 1)[0]
    g = lambda n: (re.search(r"^%s:\s*(.*)$" % n, head, re.M) or [None, None])[1]
    if g("tier") not in ("native", "full"):
        continue
    if (g("date") or "") < BIRTH:
        continue
    tc = g("toolchain") or ""
    m = re.search(r"qemu=([0-9.]+)", tc)
    if not m:
        continue
    q = m.group(1)
    tot[q] += 1

    # Same closed vocabulary as the other tool, same reason.
    segs = re.split(r"^## ", txt, flags=re.M)[1:]
    names = set()
    for seg in segs:
        if seg.startswith(("STILL-RED", "NEW-RED", "RED")):
            for line in seg.split("\n"):
                mm = re.match(r"- ([a-z0-9-]+#[^ ]+)", line)
                if mm:
                    names.add(mm.group(1))
    for n in names:
        red[n][q] += 1

QA, QB = "10.2.1", "8.2.2"
print("population: native/full reports since %s | %s n=%d | %s n=%d"
      % (BIRTH, QA, tot[QA], QB, tot[QB]))
print("full job ids only, no substrings. per-side minimum n=%d\n" % MIN_N)

rows = []
for n, c in red.items():
    ra = c[QA] / tot[QA] if tot[QA] else 0
    rb = c[QB] / tot[QB] if tot[QB] else 0
    rows.append((ra - rb, n, c[QA], ra, c[QB], rb))

rows.sort(reverse=True)
print("REVERSED — more red on the NEWER emulator (%s):" % QA)
any_rev = False
for d, n, a, ra, b, rb in rows:
    if d > 0.05 and tot[QA] >= MIN_N and tot[QB] >= MIN_N:
        print("  %-52s %s %3d/%d %5.1f%%  vs  %s %3d/%d %5.1f%%" % (n[:52], QA, a, tot[QA], 100*ra, QB, b, tot[QB], 100*rb))
        any_rev = True
if not any_rev:
    print("  NONE. No job id is materially more red on the newer emulator.")

print("\nWORST on the OLDER emulator (%s), top 8:" % QB)
for d, n, a, ra, b, rb in rows[-8:][::-1]:
    print("  %-52s %s %3d/%d %5.1f%%  vs  %s %3d/%d %5.1f%%" % (n[:52], QA, a, tot[QA], 100*ra, QB, b, tot[QB], 100*rb))
