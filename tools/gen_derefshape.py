#!/usr/bin/env python3
"""Generate test/derefshape/*.pas — the per-shape x per-arm control for `p^[i]`.

The rows are GENERATED rather than hand-written so the matrix can be widened
cheaply: the two deref walks (NodePtrElem, ResolveDerefShapeAt) are documented
as neither being a superset of the other, so the only honest way to compare
them is to enumerate the product of the axes rather than pick cases.

AXES
  spelling     how the pointer is NAMED at the index site
  element      what the pointee's element IS

The `plain` spelling is the positive control in every element kind: the one
naming that works today, same arithmetic, same element. tools/derefshape_matrix.sh
runs those first and aborts if any fails.

The `ptrelem` element kind exists for a specific historical reason: 15ec54d7a
regressed by dropping the pointer DEPTH while getting the pointee right (fixed
in bfb7b4c59). A row whose element is itself a pointer is the only kind that can
catch that class, because depth is invisible when the element is a scalar.
"""
import sys, os

D = os.path.join('test', 'derefshape')

KINDS = {
    # name      pointee element type       setup               index expr              write expr         read-back                                expected
    'fixdbl': ('array[0..3] of Double',     '',                 '[i]',                  '(i+1)*1.5',       "WriteLn(a[0]:0:2, ' ', a[3]:0:2);",     '1.50 6.00'),
    'dyndbl': ('array of Double',           'SetLength(a, 4);', '[i]',                  '(i+1)*1.5',       "WriteLn(a[0]:0:2, ' ', a[3]:0:2);",     '1.50 6.00'),
    'dynstr': ('array of AnsiString',       'SetLength(a, 4);', '[i]',                  "'v' + Chr(48+i)", "WriteLn(a[0], ' ', a[3]);",             'v0 v3'),
    # element is ITSELF a pointer: the only shape that can catch a dropped DEPTH.
    # A scalar element reads back the right number whether or not a level of
    # indirection was lost, so an all-scalar matrix is blind to that class by
    # construction, however many rows it has. Caught 381fb9e37 (an 8-byte read
    # of a 4-byte element); the same class shipped once before as 15ec54d7a.
    'ptrelem':('array of PInteger',         'SetLength(a, 4);', '[i]',                  '@nums[i]',        "WriteLn(a[0]^, ' ', a[3]^);",           '10 13'),
    # MULTI-DIM fixed pointee: DerefPtrArrayInfo splits elemCount from flatCount
    # for exactly this shape and no single-dim row exercises the split, so a
    # wrong choice between the two is invisible everywhere else.
    'md2':    ('array[0..1, 0..1] of Double','',                '[i div 2, i mod 2]',   '(i+1)*1.5',       "WriteLn(a[0,0]:0:2, ' ', a[1,1]:0:2);", '1.50 6.00'),
}

SPELL = {
    'plain':     ('  p: TP;',                 '  p := @a;',      'p',        False),
    'field':     ('  r: TR;',                 '  r.q := @a;',    'r.q',      False),
    'callres':   ('',                         '',                'GetP',     True),
    'arrayelem': ('  ap: array[0..1] of TP;', '  ap[0] := @a;',  'ap[0]',    False),
    'cast':      ('  raw: Pointer;',          '  raw := @a;',    'TP(raw)',  False),
    # `pp^^[i]` -- one more level of indirection at the SPELLING end,
    # the complement of ptrelem which adds it at the ELEMENT end.
    'nested':    ('  p: TP;\n  pp: TPP;',      '  p := @a;\n  pp := @p;', 'pp^',  False),
}

def main():
    os.makedirs(D, exist_ok=True)
    rows = []
    for kn, (ty, mk, idx, wr, rd, exp) in KINDS.items():
        for sn, (decl, init, nam, needs_fn) in SPELL.items():
            L = [f'program ds_{sn}_{kn};',
                 f'type TA = {ty}; TP = ^TA; TPP = ^TP; TR = record q: TP; end;',
                 'var', '  a: TA;']
            if kn == 'ptrelem':
                L.append('  nums: array[0..3] of Integer;')
            if decl:
                L.append(decl)
            L.append('  i: Integer;')
            if needs_fn:
                L.append('function GetP: TP; begin GetP := @a; end;')
            L.append('begin')
            if kn == 'ptrelem':
                L.append('  for i := 0 to 3 do nums[i] := 10 + i;')
            if mk:
                L.append('  ' + mk)
            if init:
                L.append(init)
            L.append(f'  for i := 0 to 3 do {nam}^{idx} := {wr};')
            L.append('  ' + rd)
            L.append('end.')
            with open(os.path.join(D, f'ds_{sn}_{kn}.pas'), 'w') as f:
                f.write('\n'.join(L) + '\n')
            rows.append((f'ds_{sn}_{kn}', exp))
    with open(os.path.join(D, 'EXPECTED'), 'w') as f:
        for n, e in rows:
            f.write(f'{n} {e}\n')
    print(f'generated {len(rows)} rows into {D}')

if __name__ == '__main__':
    sys.exit(main())
