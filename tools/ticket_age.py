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

 * A BLOCKED TICKET STILL RANKS HERE, and is marked `B`. This tool answers
   "how long has this been open", which is a different question from "can I
   work on it" -- `ready`/`next` drop a ticket with an unmet blocker, this one
   deliberately does not, because a ticket that has been gated for two months
   is exactly what an age audit is looking for. The mark exists so the reader
   can tell the two apart WITHOUT opening the file. Measured 2026-09-04: the
   oldest open ticket in the tree was gated on an unanswered Track U fork, and
   three sessions in a row each spent a full read to discover that.
   `B` means "blocked-by names something not in done/ or decided/" -- the same
   test `ready` applies, and rejected/ does NOT satisfy a blocker.

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
# Folders whose tickets SATISFY a blocker. Mirrors progress.py's
# `resolved_slugs`: done/ OR decided/, and rejected/ deliberately does NOT --
# a blocker that turned out to be a bad report never answered the question its
# dependent was waiting on.
RESOLVED = ['done', 'decided']

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

def blockers_of(body):
    """Slugs named by `blocked-by:`, inline-list or block-list form.

    A DELIBERATELY NARROWER PARSE THAN progress.py's, and it must stay that
    way: this reads the first 4000 bytes, so a ticket with a very long summary
    ABOVE its blocked-by would truncate. That direction is safe -- it drops the
    `B` mark and the row reads exactly as it did before this flag existed --
    whereas guessing from prose would invent edges. Under-report, never over.
    """
    out = []
    in_list = False
    for line in body.splitlines():
        m = re.match(r'^blocked-by:\s*\[(.*?)\]', line)
        if m:
            out += [x.strip() for x in m.group(1).split(',')]
            in_list = False
            continue
        if re.match(r'^blocked-by:\s*$', line):
            in_list = True
            continue
        m = re.match(r'^blocked-by:\s*(\S.*)$', line)
        if m:
            out += [x.strip() for x in m.group(1).split(',')]
            in_list = False
            continue
        if in_list:
            m = re.match(r'^\s*-\s*(\S.*)$', line)
            if m:
                out.append(m.group(1).strip())
                continue
            in_list = False
    return [x.strip('"\'' ) for x in out if x.strip('"\'' )]

def head(path):
    """(track, prio, old_schema, blockers) -- reads BOTH the YAML field and the
    old `**Track:** X` body form. Returns old_schema=True when only the latter."""
    track = prio = ''
    old = False
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            body = fh.read(4000)
    except OSError:
        return '', '', False, []
    for line in body.splitlines():
        if line.startswith('track:') and not track:
            track = strip(line[6:])
        elif line.startswith('prio:') and not prio:
            prio = strip(line[5:])
    if not track:
        m = re.search(r'^\s*[-*]?\s*\*\*Track:\*\*\s*([A-Za-z])', body, re.M)
        if m:
            track, old = m.group(1).upper(), True
    return track.upper(), prio, old, blockers_of(body)

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

# Slugs that satisfy a blocker. Scanned from the RESOLVED folders directly
# rather than from the open set, so a blocker that has closed stops marking its
# dependent the moment it lands, with no second index to keep in step.
resolved = set()
for d in RESOLVED:
    dp = os.path.join(ROOT, d)
    if os.path.isdir(dp):
        resolved |= {f[:-3] for f in os.listdir(dp) if f.endswith('.md')}

rows, dropped = [], 0
for d in fl:
    for f in sorted(os.listdir(os.path.join(ROOT, d))):
        if not f.endswith('.md') or f in ('README.md', 'BOARD.md', 'BOARD-brief.md'):
            continue
        tr, pr, old, bl = head(os.path.join(ROOT, d, f))
        if a.track:
            if tr != a.track.upper():
                dropped += 1
                continue
        unmet = [b for b in bl if b not in resolved]
        rows.append((first.get(f, '9999-99-99'), first.get(f, '?'), d, f[:-3], tr, pr, old,
                     unmet))
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
blk = sum(1 for r in rows if r[7])
print(pop)
print(f"{unk} with no visible add commit (renamed -- age UNMEASURABLE, not new); "
      f"{olds} on the pre-YAML `**Track:**` schema, marked *")
print(f"{blk} with an unmet `blocked-by`, marked B -- still ranked here (age is "
      f"the question), but `ready`/`next` will not offer them")
if a.track:
    print(f"{dropped} ticket(s) filtered out by --track (includes any whose lane is unset)")
print()
print(f"{'filed':10s}  {'folder':18s}  {'tk':3s} {'pri':>4s} {'':1s} slug")
for _, d, folder, slug, tr, pr, old, unmet in rows[:a.n]:
    print(f"{d:10s}  {folder:18s}  {(tr or '-')[:2]:2s}{'*' if old else ' '} {pr:>4s} "
          f"{'B' if unmet else ' '} {slug}"
          + (f"   (waits on {', '.join(unmet)})" if unmet else ''))
