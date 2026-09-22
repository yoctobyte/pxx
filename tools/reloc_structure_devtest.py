#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Positive control for reloc_resolve_check.py --check-object.

  tools/reloc_structure_devtest.py

WHAT IT GUARDS. "No relocation may point outside the section it relocates" is
an invariant BETWEEN two structures, so no per-entry assertion can see it and
`readelf -r` prints a violating entry that looks perfectly ordinary. It is also
the one relocation defect that takes the LINKER down rather than producing a
wrong value: measured 2026-09-22, `--dce --emit-obj --platform=esp` on an
IRAM-attributed routine emitted two .rela.text entries at 0x3fd68 and 0x3fe74
against a .text of 0x8788, and GNU ld died with signal 11 applying the first
(bug-a-dce-under-emit-obj-emits-an-esp-iram-object-that-segfaults-the-linker;
cause: DCE never compacted IramCallFix, so the entries kept pre-removal
offsets).

WHY THE CONTROL IS SYNTHESISED RATHER THAN CHECKED IN. The real broken object
only exists on a tree with the bug in it, and a guard whose negative case has
to be reconstructed by reverting a fix is a guard nobody runs. So this corrupts
a GOOD object in exactly the way the pass did -- push one r_offset past its
target section -- and requires the checker to reject it. That makes the control
come from the right population: it is the same object, the same section, the
same field.

AND IT ASSERTS BOTH DIRECTIONS, because a checker that rejects everything
passes a rejection test. The clean object must be accepted in the same run.

The ESP profile is the subject because that is where the defect lives, but the
check itself is target-independent -- no psABI arithmetic -- so this also
covers the architectures with no linker on this box.
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECK = os.path.join(ROOT, 'tools', 'reloc_resolve_check.py')
SRC = os.path.join(ROOT, 'test', 'esp_obj_rodata_iram.pas')
PXX = os.environ.get('PXX', os.path.join(ROOT, 'compiler', 'pascal26'))

failed = 0


def ok(msg):
    print('  ok   ' + msg)


def bad(msg, detail=''):
    global failed
    failed += 1
    print('  FAIL ' + msg)
    if detail:
        print('       ' + detail)


def check(path):
    r = subprocess.run([sys.executable, CHECK, '--check-object', path],
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


def corrupt_first_rela_text(src, dst):
    """Push entry 0 of .rela.text past the end of .text, and nothing else.

    Returns the new offset, or None if the object has no .rela.text -- which is
    itself a finding, because then the control never ran."""
    b = bytearray(open(src, 'rb').read())
    w64 = b[4] == 2
    rd = lambda o, n: int.from_bytes(b[o:o + n], 'little')
    shoff = rd(0x28, 8) if w64 else rd(0x20, 4)
    shent = rd(0x3a if w64 else 0x2e, 2)
    shnum = rd(0x3c if w64 else 0x30, 2)
    shstrndx = rd(0x3e if w64 else 0x32, 2)
    secs = []
    for i in range(shnum):
        o = shoff + i * shent
        if w64:
            secs.append(dict(name=rd(o, 4), typ=rd(o + 4, 4), off=rd(o + 24, 8),
                             size=rd(o + 32, 8), info=rd(o + 44, 4),
                             entsize=rd(o + 56, 8)))
        else:
            secs.append(dict(name=rd(o, 4), typ=rd(o + 4, 4), off=rd(o + 16, 4),
                             size=rd(o + 20, 4), info=rd(o + 28, 4),
                             entsize=rd(o + 36, 4)))
    st = secs[shstrndx]
    for s in secs:
        p = st['off'] + s['name']
        s['n'] = b[p:b.index(b'\0', p)].decode()
    rel = next((s for s in secs if s['n'] == '.rela.text' and s['entsize']), None)
    if rel is None or rel['size'] == 0:
        return None
    tgt = secs[rel['info']]
    new = tgt['size'] + 0x1000
    width = 8 if w64 else 4
    b[rel['off']:rel['off'] + width] = new.to_bytes(width, 'little')
    open(dst, 'wb').write(bytes(b))
    return new


def main():
    if not os.path.exists(SRC):
        print(f'reloc-structure devtest: SKIP -- {SRC} absent')
        return 0
    if not os.path.exists(PXX):
        print('reloc-structure devtest: SKIP -- no compiler at ' + PXX)
        return 0
    work = tempfile.mkdtemp(prefix='relstruct-')
    for target in ('riscv32', 'xtensa'):
        obj = os.path.join(work, target + '.o')
        cmd = [PXX, '--dce', '-Fu' + os.path.join(ROOT, 'lib', 'rtl'),
               '--emit-obj', '--target=' + target, '--platform=esp', SRC, obj]
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0 or not os.path.exists(obj):
            bad(f'{target}: could not build the --dce IRAM object',
                (r.stdout + r.stderr).strip().splitlines()[-1][:120]
                if (r.stdout + r.stderr).strip() else '')
            continue

        rc, out = check(obj)
        if rc == 0:
            ok(f'{target}: the --dce IRAM object is structurally clean')
        else:
            bad(f'{target}: the --dce IRAM object has out-of-range relocations',
                out.splitlines()[-1] if out else '')

        # THE CONTROL. Same object, one field moved.
        bent = os.path.join(work, target + '-corrupt.o')
        new = corrupt_first_rela_text(obj, bent)
        if new is None:
            bad(f'{target}: object has no .rela.text, so the control never ran',
                'that is a finding about the fixture, not a pass')
            continue
        rc, out = check(bent)
        if rc != 0 and 'outside' in out:
            ok(f'{target}: the checker REJECTS an offset pushed to 0x{new:x}')
        else:
            bad(f'{target}: the checker ACCEPTED a relocation outside its section',
                f'rc={rc} -- it cannot fail, so the clean row above proves nothing')

    print()
    if failed:
        print(f'reloc-structure devtest: FAILED {failed} row(s)')
        return 1
    print('reloc-structure devtest: all rows pass')
    return 0


if __name__ == '__main__':
    sys.exit(main())
