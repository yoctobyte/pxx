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
import hashlib, os, re, subprocess, sys, tempfile

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

ALIAS_TN = 'zz_alias'

def aliasprog(name, door):
    """The same door, asked through a ONE-LEVEL alias to the same builtin.

    `type zz_alias = ByteBool;` then `High(zz_alias)`. This is a different
    RECOGNITION path -- FindTypeAlias answers instead of the builtin-name table
    -- and the two are asked at different sites, so a name can be handled at one
    and not the other. The direct spelling is the one every test in the tree is
    written in, which is exactly why the alias spelling is where an untested arm
    survives.

    Measured 2026-09-06: `High(ByteBool)` is REFUSED and `type b = ByteBool;
    High(b)` answers 255 (WordBool 65535, LongBool 2147483647) against fpc's
    TRUE at both. The refusal is deliberate -- those names map to integer kinds
    to keep their C-ABI width, so answering High from the kind gives an ordinal
    -- which makes it a door DECLINING a question it cannot answer correctly
    while its sibling answers wrongly. A refusal is loud and a wrong bound is
    silent, so the accepted spelling is the worse of the two and the one nothing
    was looking at.
    """
    src = prog(name, door)
    head, body = src.split('program p;', 1)
    body = re.sub(r'\b%s\b' % re.escape(name), ALIAS_TN, body)
    return head + 'program p;\ntype ' + ALIAS_TN + ' = ' + name + ';\n' + body


# The doors this phase can ask. `decl`, `cast` and `castval` are covered for the
# alias spelling by tools/scalar_cast_door_probe.py, which asks them with the
# operand shapes that matter there; asking them again here would be a second
# instrument answering a question that already has one.
ALIAS_DOORS = ['sizeof', 'high', 'low', 'typeinfo']

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

def ask_pxx(src, d):
    """pxx only. The alias phase compares two SPELLINGS inside one compiler, so
    a second implementation adds nothing: the claim is self-consistency, not
    conformance. It also halves the run."""
    f = os.path.join(d, 'q.pas')
    open(f, 'w').write(src)
    rc, _ = run([PXX, f, os.path.join(d, 'q_pxx')], d)
    if rc != 0:
        return None
    rc, out = run([os.path.join(d, 'q_pxx')], d)
    return out.decode('latin-1').strip() if rc == 0 else None


def alias_phase(d):
    """(rows, findings). Every name asked in BOTH spellings at every ALIAS_DOOR."""
    rows, findings = [], []
    for name in ALL_NAMES:
        cells = []
        for door in ALIAS_DOORS:
            direct = ask_pxx(prog(name, door), d)
            alias  = ask_pxx(aliasprog(name, door), d)
            if direct == alias:
                cells.append('%s=.' % door)
            elif direct is None:
                cells.append('%s=ALIAS-ONLY(%s)' % (door, alias))
                findings.append((name, door, 'refused direct, answers %r through an alias' % alias))
            elif alias is None:
                cells.append('%s=DIRECT-ONLY(%s)' % (door, direct))
                findings.append((name, door, 'answers %r direct, refused through an alias' % direct))
            else:
                cells.append('%s=DIFFER(%s|%s)' % (door, direct, alias))
                findings.append((name, door, 'direct %r, alias %r' % (direct, alias)))
        rows.append('%-16s %s' % (name, '  '.join(cells)))
    return rows, findings


def artefact_id():
    """sha256 of the compiler under test, or None if it is not there."""
    if not os.path.exists(PXX):
        return None
    h = hashlib.sha256()
    with open(PXX, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()[:12]


def main():
    if not os.path.exists(PXX):
        print('no compiler at %s -- build it first' % PXX); return 2
    # The artefact is identified at the START and again at the END, and a
    # change between them is an ERROR rather than a finding.
    #
    # A mid-sweep rebuild is not random corruption: the sweep runs in name
    # order, so every row before the swap used the old compiler and every row
    # after used the new one, and the output is a CLEAN PARTITION along the
    # alphabet. Measured 2026-09-06 -- a run said `olevariant` was still broken
    # and `variant` was fixed, two spellings of the same type mapping to the
    # same kind, and the only thing separating them was that the rebuild landed
    # between them alphabetically. It reads exactly like a real per-name
    # difference, which is why it needs a guard and not a warning.
    #
    # Verified by injecting the fault, and the FIRST attempt could not fire:
    # `cp` onto the running compiler is refused with "Text file busy", so the
    # swap never happened and the guard had nothing to detect -- a control that
    # cannot be CONSTRUCTED is not a control that passed. `mv` works, and it is
    # also the faithful reproduction: make writes a new file and renames, which
    # is exactly how the real contamination arrives.
    started_at = artefact_id()
    print('compiler under test: %s' % started_at)

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
    # --- PHASE 2: the same names, asked through a one-level alias -----------
    #
    # MUST-DIFFER CONTROL FIRST. Phase 2 reports by SILENCE -- its healthy
    # output is "no name differs" -- and a comparison that can never report a
    # difference prints exactly that. So hand it two spellings that are known
    # to disagree and require it to say so; without this row, a broken ask_pxx
    # returning None for everything scores every name as agreeing.
    with tempfile.TemporaryDirectory() as d:
        a = ask_pxx(prog('byte', 'sizeof'), d)
        b = ask_pxx(aliasprog('int64', 'sizeof'), d)
        if a is None or b is None or a == b:
            print('CONTROL FAILED: the alias phase cannot report a difference '
                  '(SizeOf(byte)=%r vs SizeOf(alias of int64)=%r)' % (a, b))
            return 1
        # and the other direction: an alias to a name must not be refused
        # outright, or every row would be ALIAS-ONLY's mirror and mean nothing
        if ask_pxx(aliasprog('integer', 'sizeof'), d) is None:
            print('CONTROL FAILED: `type zz_alias = integer` was refused')
            return 1
    print()
    print('alias phase controls ok: a known-unequal pair reports unequal, '
          'and a plain alias compiles')
    with tempfile.TemporaryDirectory() as d:
        arows, afind = alias_phase(d)
    print()
    print('\n'.join(arows))
    print()
    if afind:
        print('SPELLING DISAGREES -- the same name answers differently direct and through an alias:')
        for n, door, what in afind:
            print('  %-16s %-9s %s' % (n, door, what))
        print('The direct spelling is the one every test in the tree uses, so an')
        print('arm reachable only through an alias has never been asserted on.')
    else:
        print('alias phase: every name answers identically direct and through a '
              'one-level alias, at %s' % '/'.join(ALIAS_DOORS))

    ended_at = artefact_id()
    if ended_at != started_at:
        print()
        print('ABORT: the compiler changed under the sweep (%s -> %s).' % (started_at, ended_at))
        print('Every row before the swap measured the old binary and every row after')
        print('measured the new one, so the results partition along the ALPHABET and')
        print('not along anything about the names. Re-run on a settled tree.')
        print('The window covers BOTH phases: phase 2 is another ~400 compiles and')
        print('a rebuild during them partitions the alias rows the same way.')
        return 1
    print()
    print('names=%d  cells-agree=%d  cells-differ=%d  (compiler %s throughout)'
          % (len(ALL_NAMES), agree, differ, started_at))
    if asym:
        print()
        print('ASYMMETRIC -- accepted at some doors, refused at others, fpc accepts:')
        for n, ds in asym:
            print('  %-16s refused at: %s' % (n, ' '.join(ds)))
        print('This is the SizeUInt shape. A name with working synonyms hides it.')
    else:
        print('no name is accepted at one door and refused at another')
    return 1 if afind else 0

if __name__ == '__main__':
    sys.exit(main())
