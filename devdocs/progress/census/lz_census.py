#!/usr/bin/env python3
"""Per-module lekkerzeilen census.  Classifies on the EXIT CODE, never on the
log: a segfault prints no 'error:' line, so a grep-based harness scores it
CLEAN.  Read-only with respect to the user's repo; binaries go to a temp dir."""
import subprocess, sys, os, tempfile, hashlib, glob

# Overridable, because this box has twenty sibling checkouts and a census that
# silently reads another one's compiler is the exact failure this harness is
# written to avoid.  The sha is printed below; check it against the tree you
# think you measured.
PX   = os.environ.get('PXX', os.path.join(
           os.path.dirname(os.path.dirname(os.path.dirname(
               os.path.dirname(os.path.abspath(__file__))))), 'compiler/pascal26'))
ROOT = os.environ.get('LZ_ROOT', '/home/neo/lekkerzeilen')
PKG  = ROOT + '/lekkerzeilen'
OUTD = tempfile.mkdtemp()

sha = hashlib.sha256(open(PX,'rb').read()).hexdigest()[:12]
tree = subprocess.run(['git','log','-1','--format=%h'], cwd='/home/neo/frankZ',
                      capture_output=True, text=True).stdout.strip()
dirty = subprocess.run(['git','status','--porcelain'], cwd='/home/neo/frankZ',
                       capture_output=True, text=True).stdout.strip()
lzdirty = subprocess.run(['git','status','--porcelain'], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
print(f'compiler {sha}  frankZ tree {tree}  frankZ dirty={bool(dirty)}')
print(f'lekkerzeilen dirty: {lzdirty!r}')

mods = sorted(glob.glob(PKG + '/*.py') + glob.glob(PKG + '/platform/*.py'))
rows = []
for m in mods:
    rel = os.path.relpath(m, ROOT)
    r = subprocess.run([PX, rel, os.path.join(OUTD, os.path.basename(m))],
                       cwd=ROOT, capture_output=True, timeout=300)
    out = (r.stdout + r.stderr).decode('utf-8', 'replace')
    err = next((l for l in out.splitlines() if ' error: ' in l), '')
    if r.returncode == 0:
        rows.append(('CLEAN', rel, ''))
    elif r.returncode in (-11, 139):
        rows.append(('CRASH', rel, f'SIGSEGV (rc={r.returncode})'))
    else:
        rows.append(('WALL', rel, err.split(' error: ',1)[-1][:78]))

for k in ('CLEAN','CRASH','WALL'):
    n = sum(1 for r in rows if r[0] == k)
    print(f'{k}: {n}', end='   ')
print(f'of {len(rows)}')
print()
for st, rel, why in rows:
    if st != 'CLEAN':
        print(f'  {st:5s} {rel:42s} {why}')
print()
print('CLEAN:', ' '.join(r[1].replace('lekkerzeilen/','') for r in rows if r[0]=='CLEAN'))
