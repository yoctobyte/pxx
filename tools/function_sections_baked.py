#!/usr/bin/env python3
"""Count code->code references in a pxx x86-64 object that cross a FUNCTION
boundary with no relocation -- the displacements a linker cannot re-aim.

    tools/function_sections_baked.py <obj.o>

Exit 0 when that count is zero, 1 when it is not, 2 when the object cannot be
read. Prints one summary line:

    baked-cross: <n>  direct: <d>  relocated: <r>  cuts: <c>  text-sections: <t>

WHY IT DISASSEMBLES INSTEAD OF COUNTING RELOCATIONS. A baked displacement is
not a relocation, so no census of .rela.* can see one -- the six baked `sysret'
calls that blocked per-function sections were invisible to the metric that had
just reached zero. This reads the instructions.

THE CUTS are every text section's start plus every FUNC symbol's start. On a
--function-sections object those coincide and the answer is "would a linker
that moves or drops sections break this"; on an UNSPLIT object the sections add
nothing and the answer is "would splitting at functions break this" -- which is
the POSITIVE CONTROL: an unsplit C object has ~1180, because without the flag
every internal call is baked.

ONE COORDINATE SPACE: pxx writes every text section's bytes into one contiguous
blob, so the blob is disassembled as a whole and every address is a file offset
minus the blob's start. Asserted, not assumed: a gap or an overlap between text
sections refuses with exit 2.

A reference is DIRECT when it is a rel32/rel8 call or jump, or a %rip-relative
operand; one with a relocation anywhere inside the instruction is RELOCATED and
not counted as baked. The rest cross a cut or they do not.
"""
import bisect
import os
import re
import subprocess
import sys
import tempfile


def run(*argv):
    return subprocess.run(argv, capture_output=True, text=True, check=True).stdout


def main():
    if len(sys.argv) != 2:
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    obj = sys.argv[1]
    try:
        shdrs = run('readelf', '-S', '-W', obj)
        syms = run('readelf', '-s', '-W', obj)
        rels = run('readelf', '-r', '-W', obj)
    except (OSError, subprocess.CalledProcessError) as e:
        print('function_sections_baked: cannot read %s: %s' % (obj, e), file=sys.stderr)
        return 2

    # [idx] name type addr off size es flg lk inf al -- the name may hold spaces
    # never, but its column is variable width, so split on the fixed tail.
    secs = {}
    for line in shdrs.splitlines():
        m = re.match(r'\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+([0-9a-f]+)'
                     r'\s+[0-9a-f]+\s+(\S*)\s+(\d+)\s+(\d+)\s+(\d+)', line)
        if m:
            secs[int(m.group(1))] = dict(name=m.group(2), type=m.group(3),
                                         off=int(m.group(4), 16), size=int(m.group(5), 16),
                                         flg=m.group(6), info=int(m.group(8)))
    text = sorted((i for i, s in secs.items() if s['type'] == 'PROGBITS' and 'X' in s['flg']),
                  key=lambda i: secs[i]['off'])
    if not text:
        print('function_sections_baked: %s has no executable section' % obj, file=sys.stderr)
        return 2
    base = secs[text[0]]['off']
    pos = base
    for i in text:
        if secs[i]['off'] != pos:
            print('function_sections_baked: text sections are not one contiguous blob '
                  '(section %d at file offset %#x, expected %#x) -- not a pxx object?'
                  % (i, secs[i]['off'], pos), file=sys.stderr)
            return 2
        pos += secs[i]['size']
    blob_len = pos - base

    def g(shndx, v):
        return secs[shndx]['off'] - base + v

    cuts = set(g(i, 0) for i in text)
    for line in syms.splitlines():
        p = line.split()
        if len(p) >= 7 and p[3] == 'FUNC' and p[6].isdigit() and int(p[6]) in secs \
                and int(p[6]) in text:
            cuts.add(g(int(p[6]), int(p[1], 16)))
    cuts = sorted(cuts)

    # relocation sites, in blob coordinates: a rela section names its target
    # section by sh_info, and readelf's header line names the rela section by
    # its file offset, which is unique where the name may not be.
    by_off = {s['off']: i for i, s in secs.items() if s['type'] == 'RELA'}
    sites = set()
    tgt = None
    for line in rels.splitlines():
        m = re.match(r"Relocation section '.*' at offset 0x([0-9a-f]+)", line)
        if m:
            r = by_off.get(int(m.group(1), 16))
            tgt = secs[r]['info'] if r is not None else None
            if tgt not in text:
                tgt = None
            continue
        m = re.match(r'([0-9a-f]{16})\s', line)
        if m and tgt is not None:
            sites.add(g(tgt, int(m.group(1), 16)))

    with open(obj, 'rb') as f:
        f.seek(base)
        blob = f.read(blob_len)
    with tempfile.NamedTemporaryFile(suffix='.bin') as t:
        t.write(blob)
        t.flush()
        dis = run('objdump', '-D', '-w', '-b', 'binary', '-m', 'i386:x86-64', t.name)

    def cut(a):
        return bisect.bisect_right(cuts, a)

    direct = relocated = baked = 0
    first = []
    for line in dis.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\t([0-9a-f ]+)\t(.*)', line)
        if not m:
            continue
        a = int(m.group(1), 16)
        n = len(m.group(2).split())
        ins = m.group(3)
        t = None
        b = re.match(r'(call|jmp|j[a-z]+|loop[a-z]*)\s+(?:0x)?([0-9a-f]+)\b', ins)
        if b and '*' not in ins:
            t = int(b.group(2), 16)
        elif '%rip' in ins:
            c = re.search(r'# (?:0x)?([0-9a-f]+)', ins)
            if c:
                t = int(c.group(1), 16)
        if t is None:
            continue
        direct += 1
        if any(x in sites for x in range(a, a + n)):
            relocated += 1
            continue
        if cut(a) != cut(t):
            baked += 1
            if len(first) < 5:
                first.append('%#x -> %#x  %s' % (a, t, ins.strip()))
    print('baked-cross: %d  direct: %d  relocated: %d  cuts: %d  text-sections: %d'
          % (baked, direct, relocated, len(cuts), len(text)))
    for f in first:
        print('  e.g. ' + f)
    return 1 if baked else 0


if __name__ == '__main__':
    sys.exit(main())
