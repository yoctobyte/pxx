"""Cast openers x suffix chains for the `^ / .field / [i]` walk on a CAST.

Every row is one program, compiled by pxx and by fpc 3.2.2 -Mdelphi, and the
outputs compared. The axis is the CAST SPELLING, because that is what used to
select which hand-rolled suffix loop parsed the chain -- a duplicated WALK is
invisible to a sweep that varies the chain at a fixed opener.

Three assertions, all branched on:
  * a must-differ control row -- without it, "63 agree" and "63 rows that never
    compiled" print the same;
  * a TWIN check -- fpc refuses the record-name spelling by construction, so the
    only thing that can pin those rows is the alias spelling of the same access;
  * an aim check -- no compiler at PXX exits 1 rather than reporting refusals.

PXX= to point it at another binary, CASTWALK_OUT= to keep the generated rows.
"""
import os, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.environ.get("CASTWALK_OUT") or tempfile.mkdtemp(prefix="castwalk.")
os.makedirs(D, exist_ok=True)
PXXBIN = os.environ.get("PXX", os.path.join(ROOT, "compiler", "pascal26"))
if not os.path.exists(PXXBIN):
    sys.exit("no compiler at %s -- set PXX or run `make compiler/pascal26`" % PXXBIN)
print("probe: PXX=%s" % PXXBIN)
print("probe: rows land in %s" % D)

# The axis under test is THE CAST SPELLING, because that is what selects which
# statement-side cast-target arm parses the assignment. The 25-shape sweep in
# refactor-p-one-lvalue-path-for-statements-and-expressions varied the target
# SHAPE at a fixed receiver and came back 25/25; a duplicated WALK is invisible
# to that, the same way the receiver-spelling census found two live bugs the
# shape sweep could not.
HDR = """program probe;
{$mode delphi}
{$POINTERMATH ON}
{ POINTERMATH is what gives fpc an ORACLE for `PRec(raw)[i]`. Without it fpc
  refuses every index-on-a-pointer row and the whole `[` arm reads as an
  oracle-less pxx extension -- which is how I first recorded it, wrongly. Only
  the RECORD-NAME half (`TRec(raw)[i]`, a pointer cast without a declared PRec)
  is genuinely oracle-less; the alias half is checkable, and the extension is
  pinned by having to AGREE with it. }
type
  PLongInt = ^LongInt;
  PRec = ^TRec;
  PPRec = ^PRec;
  TObj = class
  public
    Val: LongInt;
    function Twice: LongInt;
  end;
  { THE ADVANCED RECORD IS WHERE THE TWO DOT-ARM GUARDS DISAGREE. The
    record-name loop delegated EVERY name once the receiver was a class-like
    record; the pointer-alias loop delegates only names that are NOT fields and
    keeps plain fields on its own AN_FIELD builder. A plain `record` cannot tell
    them apart -- its rec id is below REC_UCLASS_BASE and neither guard fires --
    so without this type the merge's riskiest line is unasserted. }
  PAdv = ^TAdv;
  TAdv = record
    av: LongInt;
    { av2 and ad exist because `av` is at OFFSET 0 and is a LongInt: a walker
      that resolved the wrong offset, or lost the field type entirely, would
      still answer correctly for it. av2 is the same type one slot along (a
      wrong offset shows), ad is a Double (a lost type shows -- the format spec
      is silently ignored and the bit pattern prints as an integer, which is how
      bug-a-an-array-field-indexed-through-a-record-pointer-cast-loses-its-element-type
      presented). }
    av2: LongInt;
    ad: Double;
    ap: PLongInt;
    function Twice: LongInt;
    property Dbl: LongInt read Twice;
  end;
  TRec = record
    a: LongInt;
    pi: PLongInt;
    arr: array[0..3] of LongInt;
    n: PRec;
    o: TObj;
  end;
function TObj.Twice: LongInt; begin Result := Val * 2; end;
function TAdv.Twice: LongInt; begin Result := av * 2; end;
function GetP(p: Pointer): PRec; begin Result := PRec(p); end;
var
  raw: Pointer;
  adv: TAdv;
  rawa: Pointer;
  r, r2: TRec;
  pr: PRec;
  ppr: PPRec;
  iv: LongInt;
begin
  iv := 77;
  r2.a := 5;
  r.a := 11; r.pi := @iv; r.arr[1] := 33; r.n := @r2;
  r.o := TObj.Create; r.o.Val := 9;
  raw := @r; pr := @r; ppr := @pr;
  adv.av := 13; adv.av2 := 14; adv.ad := 6.5; adv.ap := @iv; rawa := @adv;
"""
FTR = "\nend.\n"

# CONTROLS ARE OPENERS, NOT EXTRA ROWS -- a chain that is wrong for everyone
# then shows up as a COLUMN rather than as a scattering of reds.
OPENERS = {
  'ctl-var':   'r',            # no cast at all
  'ctl-ptr':   'pr^',          # a plain pointer deref, no cast
  'ctl-call':  'GetP(raw)^',   # the call-result walk, a third arm again
  'recname':   'TRec(raw)^',   # record-name cast, then deref
  'recvalue':  'TRec(r)',      # record-name cast IN PLACE -- no leading ^
  'alias':     'PRec(raw)^',   # pointer-alias cast, then deref
  'alias2':    'PPRec(ppr)^^', # ...and the same arm two derefs deep
  # THE `[` ARM IS SELECTED BY AN INDEX DIRECTLY ON THE CAST, and neither the
  # `^`-headed openers above nor a chain reaching `[` through a `.` can select
  # it -- a `.` delegates to ParseClassRecordSelectors, which owns `[` itself.
  # These two openers are the record-name and pointer-alias spellings of one
  # access; test_record_name_cast_strides_by_its_record asserts they agree, and
  # fpc refuses the record-name half by construction, so it is oracle-less.
  'recidx':    'TRec(raw)[0]',
  'aliasidx':  'PRec(raw)[0]',
}
ADV_OPENERS = {
  'ctl-advvar':  'adv',
  'advalias':    'PAdv(rawa)^',
  'advrecname':  'TAdv(rawa)^',
  'advaliasidx': 'PAdv(rawa)[0]',
  'advrecidx':   'TAdv(rawa)[0]',
}
ADV_CHAINS_R = {
  'field':      '{O}.av',       # a FIELD on a class-like record: the guard split
  'field-off':  '{O}.av2',      # ...at a NONZERO offset
  'field-dbl':  '{O}.ad:0:2',   # ...and one whose TYPE the format spec depends on
  'deref-fld':  '{O}.ap^',
  'method':     '{O}.Twice',
  'prop':       '{O}.Dbl',
}
ADV_CHAINS_W = {
  'field':      ('{O}.av := 52',  'adv.av'),
  'field-off':  ('{O}.av2 := 54', 'adv.av2'),
  'field-dbl':  ('{O}.ad := 7.25', 'adv.ad:0:2'),
  'deref-fld':  ('{O}.ap^ := 53', 'iv'),
}
CHAINS_R = {
  'field':      '{O}.a',
  'deref-fld':  '{O}.pi^',
  'index':      '{O}.arr[1]',
  'deref2-fld': '{O}.n^.a',
  'method':     '{O}.o.Twice',
}
CHAINS_W = {
  'field':      ('{O}.a := 42',      'r.a'),
  'deref-fld':  ('{O}.pi^ := 43',    'iv'),
  'index':      ('{O}.arr[1] := 44', 'r.arr[1]'),
  'deref2-fld': ('{O}.n^.a := 45',   'r2.a'),
}

rows = []
for oname, o in ADV_OPENERS.items():
    for cname, c in ADV_CHAINS_R.items():
        rows.append(('read', oname, cname, '  WriteLn(%s);' % c.format(O=o)))
    for cname, (w, rb) in ADV_CHAINS_W.items():
        rows.append(('write', oname, cname,
                     '  %s;\n  WriteLn(%s);' % (w.format(O=o), rb)))
for oname, o in OPENERS.items():
    for cname, c in CHAINS_R.items():
        rows.append(('read', oname, cname, '  WriteLn(%s);' % c.format(O=o)))
    for cname, (w, rb) in CHAINS_W.items():
        rows.append(('write', oname, cname,
                     '  %s;\n  WriteLn(%s);' % (w.format(O=o), rb)))

def run(tag, src, comp):
    # THE HARNESS'S OWN MUST-DIFFER ROW. `63 agree` and `63 rows that never
    # compiled` print the same otherwise.
    if tag == 'CONTROL_must_differ' and comp == 'pxx':
        src = src.replace('WriteLn(r.a)', 'WriteLn(r.a + 1000)')
    p = os.path.join(D, 'p_%s_%s.pas' % (tag, comp))
    open(p, 'w').write(src)
    exe = os.path.join(D, 'e_%s_%s' % (comp, tag))
    cmd = (['fpc', '-Mdelphi', '-o' + exe, '-FE' + D, p] if comp == 'fpc'
           else [PXXBIN, p, exe])
    cp = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if cp.returncode != 0:
        return 'REFUSED'
    rp = subprocess.run([exe], capture_output=True, text=True, timeout=20)
    if rp.returncode != 0:
        return 'CRASH(%d)' % rp.returncode
    return rp.stdout.strip()

rows.append(('ctl', 'HARNESS', 'must-differ', '  WriteLn(r.a);'))
print('%-6s %-9s %-11s %-14s %-14s %s' % ('dir','opener','chain','fpc','pxx','verdict'))
tally = {}
results = {}
for d, oname, cname, body in rows:
    tag = ('CONTROL_must_differ' if oname == 'HARNESS'
           else '%s_%s_%s' % (d, oname.replace('-','_'), cname.replace('-','_')))
    src = HDR + body + FTR
    f, x = run(tag, src, 'fpc'), run(tag, src, 'pxx')
    if f == 'REFUSED' and x == 'REFUSED': v = 'both-refused'
    elif f == 'REFUSED':                  v = 'PXX-ONLY(no oracle)'
    elif x == 'REFUSED':                  v = 'PXX REFUSES'
    elif f == x:                          v = 'agree'
    else:                                 v = 'DIFFER'
    tally[v] = tally.get(v, 0) + 1
    results[(d, oname, cname)] = x
    print('%-6s %-9s %-11s %-14s %-14s %s' % (d, oname, cname, f, x, v))
print()
print('  '.join('%s=%d' % kv for kv in sorted(tally.items())), ' total=%d' % len(rows))

# THE ORACLE-LESS ROWS GET A TWIN CHECK, BECAUSE fpc IS SILENT ON THEM BY
# DESIGN. `TRec(raw)` is `PRec(raw)` without a declared PRec -- an extension fpc
# refuses -- so the only thing that can pin it is the spelling that DOES have an
# oracle. Every recname row must equal its alias row, every recidx row its
# aliasidx row, and every recvalue row the no-cast variable row. Without this,
# 18 rows are unasserted and a merge could change all of them silently.
TWINS = [('recname', 'alias'), ('recidx', 'aliasidx'), ('recvalue', 'ctl-var'),
         ('advrecname', 'advalias'), ('advrecidx', 'advaliasidx')]
bad = []
for a, b in TWINS:
    for (d, o, c), v in sorted(results.items()):
        if o != a:
            continue
        w = results.get((d, b, c))
        if v != w:
            bad.append('%s %s %s: %s=%r %s=%r' % (d, c, a, a, v, b, w))
if bad:
    print()
    for line in bad:
        print('TWIN MISMATCH  ' + line)
    raise SystemExit('%d oracle-less row(s) disagree with their oracle-backed twin'
                     % len(bad))
print('twin check: %d twinned rows equal their twin (18 of them oracle-less) ' %
      sum(1 for (d, o, c) in results if o in ('recname', 'recidx', 'recvalue', 'advrecname', 'advrecidx')))

if tally.get('DIFFER', 0) < 1:
    raise SystemExit('CONTROL FAILED: the must-differ row agreed, so this run '
                     'compared nothing and every agree above is vacuous')
