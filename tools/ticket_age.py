#!/usr/bin/env python3
"""Rank OPEN tickets by how long they have been open.

Age is the first commit in which a ticket's BASENAME appeared anywhere under
devdocs/progress/, so moving a ticket between folders (backlog -> working ->
blocked) does not reset its clock.

  tools/ticket_age.py                the 30 oldest
  tools/ticket_age.py -n 100
  tools/ticket_age.py --track A      one lane (see the schema note below)
  tools/ticket_age.py --parked       ALSO count rainy-day/experimental/done-followup
  tools/ticket_age.py --hist         age distribution only

THREE INSTRUMENT LIMITS -- read before quoting a number:

 * POPULATION. "Open" is the explicit folder list below, not "everything that is
   not done/". rainy-day, experimental and done-followup are deliberately parked
   and are EXCLUDED unless you pass --parked. Sweeping them in silently is how
   472 became 537 with no error and no clue. The count line always names the
   population it counted.

 * SCHEMA. The oldest tickets predate the YAML `track:` field and carry
   `**Track:** X` as body markdown instead. Both are read. This matters more
   than it sounds: reading only the YAML made `--track A` return nothing for
   exactly the old tickets an age audit is about -- a filter that answers about
   something else and never errors. Tickets with the old schema are flagged `*`,
   because being on the old schema is itself weak evidence of age.

 * AGE IS NOT EVIDENCE OF STALENESS, in either direction. An old ticket is
   usually old because it is unglamorous or hard, and both are live. This ranks
   READING ORDER. What settles staleness is running the repro or checking the
   named file/function/flag still exists. The basename key is also rename-blind:
   a renamed ticket reads as new, and `?` means UNMEASURABLE, never "recent".
"""
import subprocess, os, sys, re, collections, argparse

ROOT   = 'devdocs/progress'
OPEN   = ['urgent', 'working', 'unfinished', 'blocked', 'backlog']
PARKED = ['rainy-day', 'experimental', 'done-followup']

def first_seen():
    out = subprocess.run(
        ['git', 'log', '--reverse', '--diff-filter=A', '--date=short',
         '--format=@%ad', '--name-only', '--', ROOT + '/'],
        capture_output=True, text=True).stdout
    first, date = {}, None
    for line in out.splitlines():
        if line.startswith('@'):
            date = line[1:]
        elif line.endswith('.md') and date:
            first.setdefault(os.path.basename(line), date)
    return first

def strip(v):
    return re.split(r'\s+#', v.strip(), maxsplit=1)[0].strip().strip('"').strip()

def head(path):
    """(track, prio, old_schema) -- reads BOTH the YAML field and the old
    `**Track:** X` body form. Returns old_schema=True when only the latter."""
    track = prio = ''
    old = False
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            body = fh.read(4000)
    except OSError:
        return '', '', False
    for line in body.splitlines():
        if line.startswith('track:') and not track:
            track = strip(line[6:])
        elif line.startswith('prio:') and not prio:
            prio = strip(line[5:])
    if not track:
        m = re.search(r'^\s*[-*]?\s*\*\*Track:\*\*\s*([A-Za-z])', body, re.M)
        if m:
            track, old = m.group(1).upper(), True
    return track.upper(), prio, old

def folders(include_parked):
    want = list(OPEN) + (PARKED if include_parked else [])
    out = []
    for d in sorted(os.listdir(ROOT)):
        dp = os.path.join(ROOT, d)
        if os.path.isdir(dp) and (d in want or d.startswith('backlog')):
            out.append(d)
    return out

ap = argparse.ArgumentParser()
ap.add_argument('-n', type=int, default=30)
ap.add_argument('--track')
ap.add_argument('--parked', action='store_true')
ap.add_argument('--hist', action='store_true')
a = ap.parse_args()

first = first_seen()
fl = folders(a.parked)
rows, dropped = [], 0
for d in fl:
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        if not f.endswith('.md') or f in ('README.md', 'BOARD.md', 'BOARD-brief.md'):
            continue
        tr, pr, old = head(os.path.join(ROOT, d, f))
        if a.track:
            if tr != a.track.upper():
                dropped += 1
                continue
        rows.append((first.get(f, '9999-99-99'), first.get(f, '?'), d, f[:-3], tr, pr, old))
rows.sort()

pop = f"{len(rows)} open" + (f" on track {a.track.upper()}" if a.track else "") + \
      f" across {len(fl)} folder(s): {', '.join(fl)}"
if not a.parked:
    pop += f"\n(parked folders EXCLUDED: {', '.join(PARKED)} -- pass --parked to include)"

if a.hist:
    c = collections.Counter(r[1][:7] for r in rows)
    for m in sorted(c):
        print(f"  {m}  {c[m]:4d}  {'#' * min(60, c[m])}")
    print(f"\n{pop}")
    sys.exit(0)

unk = sum(1 for r in rows if r[1] == '?')
olds = sum(1 for r in rows if r[6])
print(pop)
print(f"{unk} with no visible add commit (renamed -- age UNMEASURABLE, not new); "
      f"{olds} on the pre-YAML `**Track:**` schema, marked *")
if a.track:
    print(f"{dropped} ticket(s) filtered out by --track (includes any whose lane is unset)")
print()
print(f"{'filed':10s}  {'folder':18s}  {'tk':3s} {'pri':>4s}  slug")
for _, d, folder, slug, tr, pr, old in rows[:a.n]:
    print(f"{d:10s}  {folder:18s}  {(tr or '-')[:2]:2s}{'*' if old else ' '} {pr:>4s}  {slug}")
