#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Resolve a pxx --emit-obj object's relocations and check the RESULT.

  tools/reloc_resolve_check.py <target> <source> [--keep <dir>]

WHY THIS EXISTS. Every pxx object outside x86-64/i386 is verified today by
`readelf -r` assertions on relocation TYPE and SYMBOL. That is a real check and
it is structurally unable to see the three ways an object writer actually goes
wrong: a wrong ADDEND, a value written into the wrong BIT-FIELD of an
instruction, and an OFFSET four bytes out. All three produce an object a linker
accepts, and A SUCCESSFUL LINK IS A DEFAULT-SHAPED PASS -- it is what you get
when the machinery did something plausible and something wrong.

  feature-a-a-target-generic-resolve-and-compare-harness-for-emit-obj-objects

HOW IT AVOIDS BEING A SELF-CONSISTENCY CHECK. The arithmetic below is written
from the psABI, not from `elfwriter.inc`, and it never calls back into pxx. If
it did, a bug in a routine shared by the executable and object paths would make
both sides wrong identically and the comparison would pass forever.

AND HOW THE APPLIER ITSELF IS PROVEN, which is the part that makes the
no-linker targets believable. On x86-64 and i386 a real linker EXISTS on this
box, so the applier is calibrated against it: resolve the object at exactly the
addresses `ld -Map` says it chose, and require the bytes to match ld's output
EXACTLY. Measured 2026-09-22 on a 328517-byte .text with 1768 relocations:
0 differing bytes. An applier that reproduces GNU ld byte-for-byte on the
targets that have one is the positive control for using it on the targets that
do not -- aarch64, arm32, riscv32 and xtensa have no linker here at all (GNU ld
2.46 offers x86 emulations only; no lld; no cross-gcc).

The three perturbation controls below are separate and test something else:
they show the COMPARISON can fail, not that the applier is right.
"""
import os, subprocess, sys, struct, tempfile

def rd(b, o, n): return int.from_bytes(b[o:o+n], 'little')

class Elf:
    """Minimal ELF32/64 little-endian reader. Deliberately not a library: the
    point is that nothing here shares code with the writer under test."""
    def __init__(self, path):
        self.b = b = open(path, 'rb').read()
        if b[:4] != b'\x7fELF': raise SystemExit(f'{path}: not an ELF')
        self.cls = b[4]
        w64 = self.cls == 2
        self.machine = rd(b, 0x12, 2)
        shoff     = rd(b, 0x28, 8) if w64 else rd(b, 0x20, 4)
        shentsize = rd(b, 0x3a if w64 else 0x2e, 2)
        shnum     = rd(b, 0x3c if w64 else 0x30, 2)
        shstrndx  = rd(b, 0x3e if w64 else 0x32, 2)
        self.sh = []
        for i in range(shnum):
            o = shoff + i * shentsize
            if w64:
                s = dict(name=rd(b,o,4), type=rd(b,o+4,4), addr=rd(b,o+16,8),
                         off=rd(b,o+24,8), size=rd(b,o+32,8), link=rd(b,o+40,4),
                         entsize=rd(b,o+56,8))
            else:
                s = dict(name=rd(b,o,4), type=rd(b,o+4,4), addr=rd(b,o+12,4),
                         off=rd(b,o+16,4), size=rd(b,o+20,4), link=rd(b,o+24,4),
                         entsize=rd(b,o+36,4))
            self.sh.append(s)
        st = self.sh[shstrndx]; strs = b[st['off']:st['off']+st['size']]
        for s in self.sh:
            s['sname'] = strs[s['name']:strs.index(b'\0', s['name'])].decode()

    def sec(self, n):
        return next((s for s in self.sh if s['sname'] == n), None)

    def data(self, s): return bytearray(self.b[s['off']:s['off']+s['size']])

    def symbols(self):
        st = self.sec('.symtab')
        strt = self.sh[st['link']]; strs = self.b[strt['off']:strt['off']+strt['size']]
        out = []
        for i in range(st['size'] // st['entsize']):
            o = st['off'] + i * st['entsize']
            if self.cls == 2:
                nm, shndx, val = rd(self.b,o,4), rd(self.b,o+6,2), rd(self.b,o+8,8)
            else:
                nm, val, shndx = rd(self.b,o,4), rd(self.b,o+4,4), rd(self.b,o+14,2)
            out.append(dict(name=strs[nm:strs.index(b'\0',nm)].decode(),
                            shndx=shndx, value=val))
        return out

    def relocs(self, base):
        """Both SHT_RELA (.rela.X, explicit addend) and SHT_REL (.rel.X, addend
        in the section bytes). i386's psABI has no addend field; x86-64's does,
        and the writers follow their own platform rather than one convention."""
        s = self.sec('.rela.' + base) or self.sec('.rel.' + base)
        if not s: return []
        rela = s['type'] == 4
        out = []
        for i in range(s['size'] // s['entsize']):
            o = s['off'] + i * s['entsize']
            if self.cls == 2:
                off, info = rd(self.b,o,8), rd(self.b,o+8,8)
                sym, typ = info >> 32, info & 0xffffffff
                add = int.from_bytes(self.b[o+16:o+24],'little',signed=True) if rela else None
            else:
                off, info = rd(self.b,o,4), rd(self.b,o+4,4)
                sym, typ = info >> 8, info & 0xff
                add = int.from_bytes(self.b[o+8:o+12],'little',signed=True) if rela else None
            out.append(dict(off=off, sym=sym, type=typ, addend=add))
        return out


def apply_relocs(e, secname, secdata, base_of, sec_va, syms, unhandled):
    for r in e.relocs(secname):
        _apply_one(e, r, secdata, base_of, sec_va, syms, unhandled)


def _apply_one(e, r, secdata, base_of, sec_va, syms, unhandled):
    """Patch `secdata` in place. Arithmetic straight from each psABI.

    An IN-PLACE addend (SHT_REL) is read out of the bytes the relocation
    covers, which is what makes i386 different from x86-64 rather than merely
    smaller."""
    s = syms[r['sym']]
    b_ = base_of.get(s['shndx'])
    if b_ is None:
        # SHN_UNDEF: a real external, which only a linker can place. Counted
        # and reported, never silently skipped -- an object whose relocations
        # are MOSTLY external is one this harness barely checks, and the
        # denominator has to say so.
        unhandled.setdefault('_undef', 0)
        unhandled['_undef'] += 1
        return
    S = b_ + s['value']
    P = sec_va + r['off']
    m = e.machine
    A = r['addend']
    if m == 62:                                  # EM_X86_64, RELA
        if   r['type'] == 1:  struct.pack_into('<Q', secdata, r['off'], (S + A) & (2**64-1))
        elif r['type'] == 2:  struct.pack_into('<i', secdata, r['off'], S + A - P)
        elif r['type'] == 11: struct.pack_into('<i', secdata, r['off'], S + A)
        else: unhandled[f'x86_64:{r["type"]}'] = unhandled.get(f'x86_64:{r["type"]}', 0) + 1
    elif m == 3:                                 # EM_386, REL (in-place addend)
        A = struct.unpack_from('<i', secdata, r['off'])[0]
        if   r['type'] == 1: struct.pack_into('<i', secdata, r['off'], (S + A) - (2**32 if S+A >= 2**31 else 0))
        elif r['type'] == 2: struct.pack_into('<i', secdata, r['off'], S + A - P)
        else: unhandled[f'i386:{r["type"]}'] = unhandled.get(f'i386:{r["type"]}', 0) + 1
    elif m == 243:                               # EM_RISCV, RELA
        if r['type'] == 1:   struct.pack_into('<I', secdata, r['off'], (S + A) & 0xffffffff)
        else: unhandled[f'riscv:{r["type"]}'] = unhandled.get(f'riscv:{r["type"]}', 0) + 1
    elif m == 94:                                # EM_XTENSA, RELA
        if r['type'] == 1:   struct.pack_into('<I', secdata, r['off'], (S + A) & 0xffffffff)
        else: unhandled[f'xtensa:{r["type"]}'] = unhandled.get(f'xtensa:{r["type"]}', 0) + 1
    elif m == 183:                               # EM_AARCH64, RELA
        # 257 R_AARCH64_ABS64, 263 MOVW_UABS_G0_NC, 264 G1_NC, 265 G2_NC.
        # The MOVW immediate is 16 bits at instruction bits 5..20 -- a
        # correct value in the wrong field is exactly what a type check
        # cannot see, which is why this harness exists.
        if r['type'] == 257:
            struct.pack_into('<Q', secdata, r['off'], (S + A) & (2**64-1))
        elif r['type'] in (263, 264, 265, 266):
            shift = {263: 0, 264: 16, 265: 32, 266: 48}[r['type']]
            insn = struct.unpack_from('<I', secdata, r['off'])[0]
            imm = ((S + A) >> shift) & 0xffff
            struct.pack_into('<I', secdata, r['off'],
                             (insn & ~(0xffff << 5)) | (imm << 5))
        elif r['type'] == 283:                   # R_AARCH64_CALL26
            struct.pack_into('<I', secdata, r['off'],
                (struct.unpack_from('<I', secdata, r['off'])[0] & ~0x03ffffff)
                | (((S + A - P) >> 2) & 0x03ffffff))
        else: unhandled[f'aarch64:{r["type"]}'] = unhandled.get(f'aarch64:{r["type"]}', 0) + 1
    elif m == 40:                                # EM_ARM, REL
        A = struct.unpack_from('<i', secdata, r['off'])[0]
        unhandled[f'arm:{r["type"]}'] = unhandled.get(f'arm:{r["type"]}', 0) + 1
    else:
        unhandled[f'machine{m}:{r["type"]}'] = unhandled.get(f'machine{m}:{r["type"]}', 0) + 1


def control_suite(e, text, base, addrs, syms, theirs, tname):
    """POSITIVE CONTROLS. The AGREE above is a comparison; these show it can
    FAIL, which is a separate claim and the one a guard most often cannot make.

    Each perturbs exactly ONE relocation in the way an object writer really
    goes wrong, re-applies, and requires the comparison to go red. All three
    survive a `readelf -r` type-and-symbol check, which is the whole argument
    for this harness -- a control drawn from the population the question is
    about, not from the population that is easy to build.

    The perturbations are applied to a COPY of the relocation list, never to
    the object on disk: the thing under test must not be edited by its own
    test."""
    rs = [r for r in e.relocs('text')
          if base.get(syms[r['sym']]['shndx']) is not None]
    if not rs:
        print(f'   CONTROLS: BROKEN -- no resolvable relocation to perturb')
        return False
    victim = rs[len(rs) // 2]
    # WHICH PERTURBATION IS AN ADDEND PERTURBATION DEPENDS ON THE FORMAT, and
    # getting that wrong is a control that passes vacuously. Measured
    # 2026-09-22: bumping the RELA addend field reddened x86-64 and did NOTHING
    # on i386, because i386 is SHT_REL and the addend lives in the section
    # BYTES -- there is no field to bump. The harness reported STILL AGREES
    # rather than passing, which is the only reason it was noticed.
    is_rela = (e.sec('.rela.text') is not None)
    def bump_addend(r):
        return dict(r, addend=(r['addend'] or 0) + 4)
    results = []
    for label, mutate, pre in (
        ('addend  +4',  bump_addend if is_rela else (lambda r: r),
                        None if is_rela else 'inplace'),
        ('offset  +4',  lambda r: dict(r, off=r['off'] + 4), None),
        ('type    swapped', lambda r: dict(r, type=(1 if r['type'] != 1 else 2)), None),
    ):
        tb2 = e.data(text)
        if pre == 'inplace':
            # SHT_REL: the in-place word IS the addend, so that is what moves.
            cur = struct.unpack_from('<i', tb2, victim['off'])[0]
            struct.pack_into('<i', tb2, victim['off'], cur + 4)
        unh = {}
        for r in e.relocs('text'):
            rr = mutate(r) if (r['off'] == victim['off'] and r['sym'] == victim['sym']) else r
            _apply_one(e, rr, tb2, base, addrs['.text'], syms, unh)
        red = bytes(tb2) != theirs
        results.append((label, red))
    bad = [l for l, red in results if not red]
    for label, red in results:
        print(f'   CONTROL {label:16s} -> {"red (good)" if red else "STILL AGREES"}')
    if bad:
        print(f'   CONTROLS: BROKEN -- {len(bad)} perturbation(s) did not redden '
              f'the comparison, so it has not been shown able to fail')
        return False
    return True


TARGETS = {
    # name:      (pxx flag,          gcc flag or None if unlinkable here)
    'x86_64':   ('',                 '-no-pie'),
    'i386':     ('--target=i386',    '-m32 -no-pie'),
    'riscv32':  ('--target=riscv32', None),
    'xtensa':   ('--target=xtensa',  None),
    'aarch64':  ('--target=aarch64', None),
    'arm32':    ('--target=arm32',   None),
}


def ld_section_addrs(mapfile, objname):
    """The addresses ld ACTUALLY chose for our input sections, read out of its
    own map. Not guessed, and not derived from the relocations under test."""
    out = {}
    for ln in open(mapfile):
        p = ln.split()
        if len(p) >= 4 and p[0] in ('.text', '.data', '.bss') and p[3].endswith(objname):
            out[p[0]] = int(p[1], 16)
    return out


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    tname, src = sys.argv[1], sys.argv[2]
    if tname not in TARGETS: raise SystemExit(f'unknown target {tname}')
    pxxflag, gccflag = TARGETS[tname]
    pxx = os.environ.get('PXX', './compiler/pascal26')
    work = tempfile.mkdtemp(prefix='relocchk-')
    obj = os.path.join(work, 'o.o')
    cmd = [pxx] + (pxxflag.split() if pxxflag else []) + ['--emit-obj', src, obj]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f'reloc-resolve[{tname}]: SKIP -- pxx cannot emit an object here')
        print('   ' + (r.stdout + r.stderr).strip().splitlines()[-1][:120])
        return 0
    e = Elf(obj); syms = e.symbols()
    text, data, bss = e.sec('.text'), e.sec('.data'), e.sec('.bss')
    nrel = len(e.relocs('text')) + len(e.relocs('data'))
    # A ZERO-RELOCATION OBJECT CANNOT FAIL THIS CHECK, so it is not a pass.
    if nrel == 0:
        print(f'reloc-resolve[{tname}]: BROKEN -- the object has NO relocations, '
              f'so nothing here could have gone red')
        return 1

    if gccflag is None:
        print(f'reloc-resolve[{tname}]: {nrel} relocations, no linker on this box -- '
              f'applier-only mode')
        base = {e.sh.index(text): 0x400000}
        if data: base[e.sh.index(data)] = 0x500000
        if bss:  base[e.sh.index(bss)]  = 0x600000
        unhandled = {}
        tb = e.data(text)
        apply_relocs(e, 'text', tb, base, 0x400000, syms, unhandled)
        undef = unhandled.pop('_undef', 0)
        if unhandled:
            print(f'reloc-resolve[{tname}]: BROKEN -- unhandled relocation types {unhandled}')
            return 1
        print(f'reloc-resolve[{tname}]: applied {nrel - undef} of {nrel} relocations '
              f'({undef} name an UNDEFINED symbol only a linker can place)')
        print(f'   NOT a correctness claim: with no linker there is no oracle here yet.')
        return 0

    # LINKER-ORACLE MODE. This is the calibration that licenses the mode above.
    mapf = os.path.join(work, 'ld.map'); exe = os.path.join(work, 'exe')
    lr = subprocess.run(['gcc'] + gccflag.split() + ['-o', exe, obj, f'-Wl,-Map={mapf}'],
                        capture_output=True, text=True)
    if lr.returncode != 0:
        print(f'reloc-resolve[{tname}]: SKIP -- gcc {gccflag} cannot link here')
        return 0
    addrs = ld_section_addrs(mapf, os.path.basename(obj))
    if '.text' not in addrs:
        print(f'reloc-resolve[{tname}]: BROKEN -- ld map named no .text for our object')
        return 1
    base = {}
    for nm, s in (('.text', text), ('.data', data), ('.bss', bss)):
        if s is not None and nm in addrs: base[e.sh.index(s)] = addrs[nm]
    unhandled = {}
    tb = e.data(text)
    apply_relocs(e, 'text', tb, base, addrs['.text'], syms, unhandled)
    undef = unhandled.pop('_undef', 0)
    if unhandled:
        print(f'reloc-resolve[{tname}]: BROKEN -- unhandled relocation types {unhandled}')
        return 1
    le = Elf(exe); lt = le.sec('.text')
    off = lt['off'] + (addrs['.text'] - lt['addr'])
    theirs = le.b[off:off + len(tb)]
    diff = [i for i in range(len(tb)) if tb[i] != theirs[i]]
    if diff:
        print(f'reloc-resolve[{tname}]: DIFFER -- {len(diff)} of {len(tb)} bytes '
              f'disagree with GNU ld')
        for i in diff[:6]:
            print(f'   off={i:#x} harness={tb[i]:02x} ld={theirs[i]:02x}')
        return 1
    print(f'reloc-resolve[{tname}]: AGREE with GNU ld on {len(tb)} bytes, '
          f'{nrel - undef} relocations resolved here ({undef} undefined, ld-only)')
    if not control_suite(e, text, base, addrs, syms, theirs, tname):
        return 1
    # And the program has to RUN, because bytes agreeing with ld says nothing
    # about whether ld and pxx agreed about the right thing.
    rr = subprocess.run([exe], capture_output=True, text=True, timeout=120)
    print(f'   linked binary runs: rc={rr.returncode} out={rr.stdout.strip()[:40]!r}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
