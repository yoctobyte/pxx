#!/usr/bin/env python3
"""Unit-width sweep: total bytecode size for instruction units of W = 4..64 bits.

Usage: sweep.py IR_DUMP SRC_DIR NATIVE_OBJ [NAME,...]   (same arguments as census.py)
Prints one line per W: W, best register-field width r, opcode bits o, units, bytes.

Model, per instruction (operands taken from the IR, cost model as census.py):
  First unit: o = W - 2r opcode bits, then two r-bit fields. One opcode value
  is the escape, so 2^o - 1 opcodes fit (ranked by static frequency).
  A short form fits when the opcode fits, every register is < 2^r (the
  procedure's peak register need), and the payload (immediate, offset,
  literal/global/call index) fits in the operand bits the registers leave.
  Otherwise the long form: one unit carrying the escape, then a wide encoding
  of 8 opcode bits + 8 bits per register + the payload's real width, in
  ceil(bits / W) further units.
"""
import sys, io, contextlib, runpy, math, collections
args = sys.argv[1:]
sys.argv = [sys.argv[0].replace('sweep.py', 'census.py')] + args
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    g = runpy.run_path(sys.argv[0])
ap, peaks, OPS, CMP = g['ap'], g['peaks'], g['OPS'], g['CMP']

def sbits(v):            # bits for a signed value
    v = abs(v); return max(1, v.bit_length() + 1)
def ubits(n):            # bits for an index 0..n-1
    return max(1, (max(n, 1) - 1).bit_length())

recs = []                # (op, nregs, payload_bits, regbits)
globs = set(); procs_called = set()
for p in ap:
    for n in p['n']:
        if n['k'] in ('load_sym', 'store_sym') and n['sk'] == 1: globs.add(n['sym'])
        if n['k'] == 'call': procs_called.add(n['a'])
gbits, cbits = ubits(len(globs)), ubits(1024)
for p, pk in zip(ap, peaks):
    N = p['n']; rb = ubits(pk)
    users = collections.defaultdict(list)
    for i, n in enumerate(N):
        if n['k'] == 'binop': refs = [n['a'], n['b']]
        elif n['k'] in ('store_sym', 'jump_if_false'): refs = [n['b']]
        elif n['k'] in ('arg', 'not', 'neg', 'load_mem', 'field'): refs = [n['a']]
        elif n['k'] in ('store_mem', 'index'): refs = [n['a'], n['b']]
        else: refs = []
        for r in refs:
            if 0 <= r < len(N): users[r].append(i)
    lits = sum(1 for n in N if n['k'] == 'const_str'); lb = ubits(lits)
    # instruction positions, for branch offsets
    pos = 0; labelpos = {}; plan = []
    for i, n in enumerate(N):
        k = n['k']; rec = None
        if k == 'load_sym' and n['sk'] == 1: rec = ('ld.global', 1, gbits)
        elif k == 'store_sym':
            v = N[n['b']] if 0 <= n['b'] < len(N) else None
            if n['tk'] == 23 or (v and v['tk'] == 23 and v['k'] in ('load_sym', 'const_str')): rec = ('str.assign', 2, 0)
            elif n['sk'] == 1: rec = ('st.global', 1, gbits)
            elif v and v['k'] == 'load_sym': rec = ('mov', 2, 0)
        elif k == 'const_int':
            us = [N[u]['k'] for u in users[i]]
            if not (us and all(u in ('binop', 'jump_if_false') for u in us) and -64 <= n['iv'] < 64):
                rec = ('li', 1, sbits(n['iv']))
        elif k == 'binop':
            o = OPS.get(n['c'], 'op%d' % n['c'])
            us = [N[u]['k'] for u in users[i]]
            if not (o in CMP and us == ['jump_if_false']):
                b = N[n['b']] if 0 <= n['b'] < len(N) else None
                if b and b['k'] == 'const_int' and -64 <= b['iv'] < 64: rec = (o + 'i.' + str(n['tk']), 1, sbits(b['iv']))
                else: rec = (o + '.' + str(n['tk']), 2, 0)
        elif k == 'jump_if_false':
            cond = N[n['b']] if 0 <= n['b'] < len(N) else None
            if cond and cond['k'] == 'binop' and OPS.get(cond['c']) in CMP:
                rec = ('br.' + OPS[cond['c']], 2, ('L', n['a']))
            else: rec = ('br.false', 1, ('L', n['a']))
        elif k == 'jump': rec = ('jmp', 0, ('L', n['a']))
        elif k == 'label': labelpos[n['iv']] = pos
        elif k == 'terminate': rec = ('ret', 0, 0)
        elif k == 'call': rec = ('call', 1, cbits)
        elif k == 'arg':
            v = N[n['a']] if 0 <= n['a'] < len(N) else None
            if v and v['k'] in ('load_sym', 'const_int', 'const_str'): rec = ('mov.arg', 2, 0)
        elif k == 'const_str': rec = ('ld.str', 1, lb)
        elif k == 'lea': rec = ('lea', 2, 0)
        elif k in ('load_mem', 'store_mem'):
            rec = (k, 2, 0)
        elif k in ('block', 'nop', 'field', 'load_sym', 'arg'): rec = None
        else: rec = (k, 2, 0)
        if rec: plan.append((pos, rec)); pos += 1
    for at, (op, nr, pay) in plan:
        if isinstance(pay, tuple):
            pay = sbits(labelpos.get(pay[1], at) - at)
        recs.append((op, nr, pay, rb))

rank = {o: i for i, (o, _) in enumerate(collections.Counter(r[0] for r in recs).most_common())}
OPW = 8                    # wide opcode bits in the long form
print('# instructions', len(recs), ' distinct ops', len(rank))
for W in range(4, 65):
    best = None
    for r in range(0, (W - 1) // 2 + 1):
        o = W - 2 * r
        if o < 1: continue
        units = 0
        for op, nr, pay, rb in recs:
            free = 2 * r - nr * r                  # operand bits the registers leave
            short = rank[op] < (1 << o) - 1 and (nr == 0 or rb <= r) and pay <= free
            if short: units += 1
            else: units += 1 + math.ceil((OPW + 8 * nr + pay) / W)
        b = units * W / 8
        if best is None or b < best[3]: best = (r, o, units, b)
    print(W, best[0], best[1], best[2], int(best[3]))
