#!/usr/bin/env python3
"""One postfix chain, two ROUTES: off a call RESULT and off a pointer VARIABLE.

`f()^.a`, `f()^[i]`, `f()^[i]` through a default property -- every one of these
is the same `^ / .field / [i]` chain, and pxx parses it with two different
loops. `ParseCastPostfixSuffix` (the merged cast one) and
`ApplyCallResultPtrSuffix` (the call-result one) have the same three arms and
the same terminator set, and the second is 89 lines shorter.

THE AXIS IS THE ROUTE, and it has to be, because both loops are correct for the
shapes their own tests use. A pointer VARIABLE holding the identical address
walks the rich loop; a call returning that same address walks the short one. So
every row is written twice against one oracle and the two must agree -- the
variable route is a control that cannot be wrong for a reason the call route is
also wrong for.

The rows are chosen from a HELPER CENSUS rather than from imagination: the
call-result loop never calls FindDefaultProp, TypeIsFrozenString, IsNodeArray,
ResolveDerefShape, NodeMetaclassCi or ParseMetaclassMemberTail, and the cast
loop calls all six. Each absent helper is a capability the call route may not
have, so each one gets a row. Two of them are live today.

Positive controls, both branched on:
  - a must-differ row (the two routes read different indices), so a harness that
    compares nothing still reports a disagreement;
  - an aim check that the program was BUILT and RAN, because a comparison whose
    inputs were never produced cannot fail.
"""
import os, subprocess, sys, tempfile

ROOT = os.environ.get('PXXROOT',
                      os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.path.isdir(os.path.join(ROOT, 'compiler')):
    sys.exit('no compiler/ under %s -- run the tools/ copy, or set PXXROOT' % ROOT)
PXX = os.environ.get('PXX', os.path.join(ROOT, 'compiler', 'pascal26'))
FPC = os.environ.get('FPC', 'fpc')

PRELUDE = r"""{$mode delphi}
program crs;
type
  PRec = ^TRec;
  TRec = record a: LongInt; d: Double; end;
  TArr = array[0..3] of LongInt;
  PArr = ^TArr;
  TBox = class
    data: TArr;
    function GetIt(i: LongInt): LongInt;
    property Items[i: LongInt]: LongInt read GetIt; default;
  end;
  PBox = ^TBox;
  PStr = ^ShortString;
var
  gr: TRec; ga: TArr; gb: TBox; gs: ShortString;
function TBox.GetIt(i: LongInt): LongInt; begin Result := data[i] + 100; end;
function FR: PRec;  begin Result := @gr; end;
function FA: PArr;  begin Result := @ga; end;
function FB: PBox;  begin Result := @gb; end;
function FS: PStr;  begin Result := @gs; end;
var vr: PRec; va: PArr; vb: PBox; vs: PStr;
begin
  gr.a := 11; gr.d := 2.5;
  ga[0] := 20; ga[1] := 21; ga[2] := 22; ga[3] := 23;
  gb := TBox.Create; gb.data[0] := 30; gb.data[1] := 31;
  gs := 'abcde';
  vr := @gr; va := @ga; vb := @gb; vs := @gs;
"""

# (label, call-route expression, variable-route expression, absent helper it probes)
ROWS = [
    ('rec-field',  'FR^.a',        'vr^.a',        '-'),
    ('rec-double', 'FR^.d:0:1',    'vr^.d:0:1',    '-'),
    ('arr-index',  'FA^[2]',       'va^[2]',       'IsNodeArray / ResolveDerefShape'),
    ('defprop',    'FB^[1]',       'vb^[1]',       'FindDefaultProp'),
    ('prop-named', 'FB^.Items[1]', 'vb^.Items[1]', '-'),
    ('method',     'FB^.GetIt(0)', 'vb^.GetIt(0)', '-'),
    ('frozen-str', 'FS^[2]',       'vs^[2]',       'TypeIsFrozenString'),
    # the must-differ control: the two routes are DELIBERATELY not the same
    # access, so a run in which nothing is compared still reports a mismatch.
    ('__CONTROL__', 'FA^[0]',      'va^[3]',       'must differ'),
]


def build_and_run(d):
    src = PRELUDE + ''.join(
        "  WriteLn('%s call=', %s, ' var=', %s);\n" % (lbl, c, v)
        for lbl, c, v, _ in ROWS) + "  WriteLn('CRS END');\nend.\n"
    f = os.path.join(d, 'crs.pas')
    open(f, 'w').write(src)
    out = {}
    for who, cmd, exe in (
            ('pxx', [PXX, f, os.path.join(d, 'crs_pxx')], os.path.join(d, 'crs_pxx')),
            ('fpc', [FPC, '-viwn', '-O1', '-FE' + d, '-Fu' + d, f], os.path.join(d, 'crs'))):
        p = subprocess.run(cmd, cwd=d, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if p.returncode != 0:
            out[who] = None
            continue
        r = subprocess.run([exe], cwd=d, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out[who] = r.stdout.decode('latin-1') if r.returncode == 0 else None
    return out


def cells(text):
    got = {}
    for line in (text or '').split('\n'):
        if ' call=' not in line:
            continue
        lbl = line.split(' call=')[0].strip()
        rest = line.split(' call=', 1)[1]
        call, _, var = rest.partition(' var=')
        got[lbl] = (call.strip(), var.strip())
    return got


def main():
    with tempfile.TemporaryDirectory() as d:
        out = build_and_run(d)
    # AIM: assert both artefacts ran before comparing anything they produced.
    for who in ('pxx', 'fpc'):
        if out[who] is None or 'CRS END' not in out[who]:
            print('ABORT: %s did not build-and-run the probe to completion.' % who)
            print('A comparison whose inputs were never produced cannot fail.')
            return 2
    p, f = cells(out['pxx']), cells(out['fpc'])
    twin_bad = agree = differ = 0
    ctl_fired = False
    print('%-12s %-24s %-24s' % ('row', 'pxx  call | var', 'fpc  call | var'))
    for lbl, _, _, helper in ROWS:
        pc, pv = p.get(lbl, ('?', '?'))
        fc, fv = f.get(lbl, ('?', '?'))
        if lbl == '__CONTROL__':
            ctl_fired = (pc != pv) and (fc != fv)
            note = 'control: routes differ by construction'
        else:
            same_route = (pc == pv)
            same_oracle = (pc == fc and pv == fv)
            if not same_route:
                twin_bad += 1
            if same_oracle:
                agree += 1
            else:
                differ += 1
            note = 'ROUTES DISAGREE  <- %s' % helper if not same_route else ''
        print('%-12s %-24s %-24s %s' % (lbl, '%s | %s' % (pc[:9], pv[:9]),
                                        '%s | %s' % (fc[:9], fv[:9]), note))
    print()
    print('rows=%d  agree-with-fpc=%d  differ=%d  route-mismatches=%d'
          % (len(ROWS) - 1, agree, differ, twin_bad))
    if not ctl_fired:
        print('CONTROL FAILED: the must-differ row came back equal in one of the')
        print('two compilers, so this harness is not comparing the two routes.')
        return 1
    print('control ok: the must-differ row differs in both compilers')
    return 1 if twin_bad else 0


if __name__ == '__main__':
    sys.exit(main())
