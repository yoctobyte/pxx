#!/usr/bin/env python3
"""Ask ONE type name at EVERY door, and compare each door against fpc 3.2.2.

The five-doors ticket is about a name being recognised in several places. The
failure that costs is not a door disagreeing about a VALUE -- it is a name that
works at some doors and is REFUSED at others, because every working door tells
you the name is fine. `SizeUInt` was exactly that: the cast door and SizeOf
answered like fpc while High/Low said "undefined variable", and its three
synonyms SizeInt/NativeUInt/PtrUInt all worked, so nothing was ever loud.

Doors asked here, each in its own program so one refusal cannot take the rest:

  decl      var x: N;                     -- does the DECLARATION path know it
  sizeof    SizeOf(N)                     -- the type's own size (not an expr's:
                                             SizeOf of an EXPRESSION is
                                             implementation latitude per
                                             CLAUDE.md and is never compared)
  cast      var x: N; x := N(v);          -- store in the DECLARED type, which
                                             is CLAUDE.md's compatibility test
  castval   Ord(N(233))                   -- ordinal names only
  high/low  High(N) / Low(N)
  typeinfo  TypeInfo(N) <> nil

Names are read out of the compiler source (the UNION of OrdinalNameToTk and
BuiltinScalarTypeKind) so the sweep cannot go stale against the tables it is
about, and so a name ADDED to either table is swept without editing this file.

Positive controls, both branched on:
  - `zzznosuchtype` must be refused at every door by BOTH compilers. A door that
    accepts it is not measuring the name.
  - `integer` must be accepted at every door by both. A door that refuses it is
    broken independently of the name under test.
Without the first, a probe where every program fails to build reports a clean
"agree" on every row.
"""
import os, re, subprocess, sys, tempfile

# The repo root is derived from this file's location so the committed copy in
# tools/ needs no configuration -- but a copy run from a scratch directory would
# then compute a root that has no compiler/ in it and die on the FIRST read,
# which reads as "the probe is broken" rather than "you ran the wrong copy".
# PXXROOT overrides it, and the root is CHECKED here rather than at first use.
ROOT = os.environ.get('PXXROOT',
                      os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.path.isdir(os.path.join(ROOT, 'compiler')):
    sys.exit('no compiler/ under %s -- run the tools/ copy, or set PXXROOT' % ROOT)
PXX  = os.environ.get('PXX', os.path.join(ROOT, 'compiler', 'pascal26'))
FPC  = os.environ.get('FPC', 'fpc')

def table_names(fn):
    src = open(os.path.join(ROOT, 'compiler', 'pasparser_lval.inc')).read().split('\n')
    i = next(n for n, l in enumerate(src) if l.startswith('function ' + fn))
    out = []
    while not src[i].startswith('end;'):
        out += re.findall(r"CaseEqual\(nm, '([a-z0-9_]+)'\)", src[i]); i += 1
    return out

ORD_NAMES = table_names('OrdinalNameToTk')
ALL_NAMES = sorted(set(ORD_NAMES) | set(table_names('BuiltinScalarTypeKind')))

# {$mode delphi} is NOT decoration. Without a mode directive fpc compiles in
# mode `fpc`, where `Integer` is a SMALLINT: the first run of this probe
# reported SizeOf(Integer) as 4|2 and High(Integer) as 2147483647|32767 and
# they read as three defects. They were one missing line, and the oracle was
# answering honestly about a different type than the one pxx means. Every
# committed probe here carries the same directive for the same reason.
HDR = '{$mode delphi}\n'

# Character kinds get their bound printed as an ORDINAL. `WriteLn(High(WideChar))`
# measures the OUTPUT ENCODING, not the bound: pxx emits the UTF-8 bytes of
# U+FFFF and fpc emits `?`, so the row reports a divergence that has nothing to
# do with High. It showed up the moment those names STOPPED being refused
# (26742a0ca) -- before the fix the cell read PXX-REFUSES and the confound was
# invisible behind it. Ord() is applied ONLY to these names, never as a uniform
# printer: `Ord(q)` for a QWord answers -1 in pxx against fpc's
# 18446744073709551615, which is intermediate-overload latitude per CLAUDE.md
# and would be a second phantom row.
CHARISH = {'char', 'ansichar', 'widechar', 'unicodechar', 'ucs4char'}


def ordwrap(expr, name):
    if name in CHARISH:
        return 'Ord(%s)' % expr
    return expr

def prog(name, door):
    if door == 'decl':
        return HDR + "program p; var x: %s; begin WriteLn('ok'); if SizeOf(x) < 0 then WriteLn(1); end." % name
    if door == 'sizeof':
        return HDR + "program p; begin WriteLn(SizeOf(%s)); end." % name
    if door == 'cast':
        return HDR + "program p; var x: %s; y: LongInt; begin y := 233; x := %s(y); WriteLn('ok'); end." % (name, name)
    if door == 'castval':
        return HDR + "program p; begin WriteLn(Ord(%s(233))); end." % name
    if door == 'high':
        return HDR + "program p; begin WriteLn(%s); end." % ordwrap('High(%s)' % name, name)
    if door == 'low':
        return HDR + "program p; begin WriteLn(%s); end." % ordwrap('Low(%s)' % name, name)
    if door == 'typeinfo':
        return HDR + "program p; begin WriteLn(TypeInfo(%s) <> nil); end." % name
    raise AssertionError(door)

DOORS = ['decl', 'sizeof', 'cast', 'castval', 'high', 'low', 'typeinfo']

def run(cmd, cwd):
    try:
        p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=60)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, b'TIMEOUT'

def ask(src, d):
    """Return the program's output, or None if either compiler refused."""
    f = os.path.join(d, 'p.pas')
    open(f, 'w').write(src)
    res = {}
    rc, _ = run([PXX, f, os.path.join(d, 'p_pxx')], d)
    if rc != 0:
        res['pxx'] = None
    else:
        rc, out = run([os.path.join(d, 'p_pxx')], d)
        res['pxx'] = out.decode('latin-1').strip() if rc == 0 else None
    rc, _ = run([FPC, '-viwn', '-O1', '-FE' + d, '-Fu' + d, f], d)
    if rc != 0:
        res['fpc'] = None
    else:
        rc, out = run([os.path.join(d, 'p')], d)
        res['fpc'] = out.decode('latin-1').strip() if rc == 0 else None
    return res

def main():
    if not os.path.exists(PXX):
        print('no compiler at %s -- build it first' % PXX); return 2
    rows, agree, differ, asym = [], 0, 0, []
    # --- positive controls, both branched on ---
    with tempfile.TemporaryDirectory() as d:
        for door in DOORS:
            r = ask(prog('zzznosuchtype', door), d)
            if r['pxx'] is not None:
                print('CONTROL FAILED: door %s accepted zzznosuchtype in pxx (%r)' % (door, r['pxx']))
                return 1
        for door in DOORS:
            r = ask(prog('integer', door), d)
            if r['pxx'] is None or r['fpc'] is None:
                print('CONTROL FAILED: door %s refused `integer` (pxx=%r fpc=%r)'
                      % (door, r['pxx'], r['fpc']))
                return 1
    print('controls ok: every door refuses zzznosuchtype and accepts integer, in both compilers')
    print()
    for name in ALL_NAMES:
        with tempfile.TemporaryDirectory() as d:
            doors = [x for x in DOORS if x != 'castval' or name in ORD_NAMES]
            cells, refused_here = [], []
            for door in doors:
                r = ask(prog(name, door), d)
                if r['pxx'] == r['fpc']:
                    cells.append('%s=.' % door); agree += 1
                elif r['pxx'] is None and r['fpc'] is not None:
                    cells.append('%s=PXX-REFUSES' % door); differ += 1
                    refused_here.append(door)
                elif r['fpc'] is None and r['pxx'] is not None:
                    cells.append('%s=pxx-only' % door); agree += 1
                else:
                    cells.append('%s=DIFFER(%s|%s)' % (door, r['pxx'], r['fpc'])); differ += 1
            # the SizeUInt signature: refused at some doors, accepted at others,
            # while fpc accepts everywhere it was asked
            if refused_here and len(refused_here) < len(doors):
                asym.append((name, refused_here))
            rows.append('%-16s %s' % (name, '  '.join(cells)))
    print('\n'.join(rows))
    print()
    print('names=%d  cells-agree=%d  cells-differ=%d' % (len(ALL_NAMES), agree, differ))
    if asym:
        print()
        print('ASYMMETRIC -- accepted at some doors, refused at others, fpc accepts:')
        for n, ds in asym:
            print('  %-16s refused at: %s' % (n, ' '.join(ds)))
        print('This is the SizeUInt shape. A name with working synonyms hides it.')
    else:
        print('no name is accepted at one door and refused at another')
    return 0

if __name__ == '__main__':
    sys.exit(main())
