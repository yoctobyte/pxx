#!/usr/bin/env python3
"""Rank OPEN tickets by how long they have been open.

Age is measured as the first commit in which a ticket's BASENAME appeared
anywhere under devdocs/progress/, so moving a ticket between folders (backlog ->
working -> blocked) does not reset its clock.

  tools/ticket_age.py            the 30 oldest
  tools/ticket_age.py -n 100     the 100 oldest
  tools/ticket_age.py --track A  one lane
  tools/ticket_age.py --hist     age distribution only

INSTRUMENT LIMITS -- read these before quoting a number:
 * The key is the basename. A ticket RENAMED (its slug changed) reads as new on
   the day of the rename, and one whose file was added outside devdocs/progress
   reads as `?`. Two currently do. `?` means "this tool cannot see it", NOT
   "recently filed" -- do not let it sort as either.
 * AGE IS NOT EVIDENCE OF STALENESS. An old ticket may be perfectly live and
   merely unglamorous; a ticket filed yesterday may already be obsolete. This
   ranks READING ORDER only. What settles staleness is running the repro or
   checking that the named file/function/flag still exists.
"""
import subprocess, os, sys, collections, argparse

ROOT = 'devdocs/progress'
CLOSED = {'done', 'rejected', 'decided', 'tstate', 'float'}

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

def field(path, key):
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            for line in fh:
                if line.startswith(key + ':'):
                    return line.split(':', 1)[1].strip().strip('"')
                if line.startswith('summary:'):
                    break
    except OSError:
        pass
    return ''

def open_tickets():
    for d in sorted(os.listdir(ROOT)):
        dp = os.path.join(ROOT, d)
        if not os.path.isdir(dp) or d in CLOSED:
            continue
        for f in sorted(os.listdir(dp)):
            if f.endswith('.md') and f not in ('README.md', 'BOARD.md', 'BOARD-brief.md'):
                yield d, f, os.path.join(dp, f)

ap = argparse.ArgumentParser()
ap.add_argument('-n', type=int, default=30)
ap.add_argument('--track')
ap.add_argument('--hist', action='store_true')
a = ap.parse_args()

first = first_seen()
rows = []
for d, f, p in open_tickets():
    tr = field(p, 'track')
    if a.track and tr.upper() != a.track.upper():
        continue
    rows.append((first.get(f, '9999-99-99'), first.get(f, '?'), d, f[:-3], tr, field(p, 'prio')))
rows.sort()

if a.hist:
    c = collections.Counter(r[1][:7] for r in rows)
    for m in sorted(c):
        print(f"  {m}  {c[m]:4d}  {'#' * min(60, c[m])}")
    print(f"\n  total open: {len(rows)}")
    sys.exit(0)

print(f"{len(rows)} open tickets" + (f" on track {a.track.upper()}" if a.track else "") +
      f"; {sum(1 for r in rows if r[1]=='?')} with no visible add commit (renamed -- age unknown, NOT new)\n")
print(f"{'filed':10s}  {'folder':18s}  {'tk':3s} {'pri':>4s}  slug")
for _, d, folder, slug, tr, pr in rows[:a.n]:
    print(f"{d:10s}  {folder:18s}  {tr[:3]:3s} {pr:>4s}  {slug}")
