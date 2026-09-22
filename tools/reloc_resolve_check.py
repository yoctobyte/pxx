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

AND BE PRECISE ABOUT WHAT THE ld CALIBRATION LICENSES, BECAUSE IT IS LESS THAN
IT SOUNDS (frankuser, 2026-09-22). Agreeing with GNU ld on x86-64 and i386
validates the SHARED FRAMEWORK -- the ELF reader, section addressing, the apply
loop, the control discipline -- and it does NOT validate the PER-TARGET
ARITHMETIC, which is written fresh from each psABI and is exactly the part that
differs per target. When the aarch64 arm runs, its movz/movk field maths has no
external check from this calibration at all. Half of that gap is closable
cheaply and should be closed when that arm lands: clang cannot EMIT a MOVW_UABS
relocation, but it can ASSEMBLE the instruction, so `movz x0, #0x1234, lsl #16`
through clang's assembler is an external oracle for FIELD ENCODING, leaving
only WHICH VALUE goes in the field resting on one reading of the psABI.

NO EMULATOR AND NO WALL-TIME QUANTITY LIVE ANYWHERE IN THIS MEASUREMENT, and
that is a property to preserve rather than a coincidence. It resolves bytes and
compares bytes, then runs the NATIVELY linked x86-64 and i386 binaries -- so
neither machine load nor a qemu version can move a verdict. Measured 2026-09-22
while a peer put deliberate load on this box and then ran an unnice'd full
tier: a `gate.sh quick` went from ~2min to ~9min and this harness's output did
not change by a byte. A future aarch64 or arm32 leg that runs under qemu would
be the FIRST emulator dependency here, and it would inherit a real hazard --
on seven a qemu 8.2.2 -> 10.2.1 upgrade on 2026-09-05 flipped a red row green
and moved a tier wall from ~227s to ~151s in the same instant, so wall time and
emulator version are collinear across that date (frankh-c0, 2026-09-22).
Record `toolchain:` with any such row; its ABSENCE is a date stamp, not missing
data.

A SKIP CARRIES THE COMPILER'S OWN DIAGNOSTIC, ALWAYS. A silent skip is a
hiding place: a whole target's crtl was unreachable on xtensa behind one, and
nothing in the tier drove it, so nobody had read the refusal. Printing it is
what turned "this target has no probe yet" into
bug-a-xtensa-cannot-lower-a-store-through-a-pointer-... A skip that names its
reason is a finding generator; a skip that does not is where findings go to
die.

A RELOCATION AGAINST AN UNDEFINED SYMBOL IS APPLIED, NOT SKIPPED. A linker's
only contribution to one is choosing the address, so the harness chooses it --
see undef_addr. Skipping them would have excluded the entire class this exists
for on aarch64, where an extern is reached through movz/movk and every one of
those relocations names an undefined symbol.
"""
import os, subprocess, sys, struct, tempfile

def rd(b, o, n): return int.from_bytes(b[o:o+n], 'little')

class Elf:
    """Minimal ELF32/64 little-endian reader. Deliberately not a library: the
    point is that nothing here shares code with the writer under test."""
    def __init__(self, path):
        self.path = path
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
                s = dict(name=rd(b,o,4), type=rd(b,o+4,4), flags=rd(b,o+8,8),
                         addr=rd(b,o+16,8), off=rd(b,o+24,8), size=rd(b,o+32,8),
                         link=rd(b,o+40,4), entsize=rd(b,o+56,8))
            else:
                s = dict(name=rd(b,o,4), type=rd(b,o+4,4), flags=rd(b,o+8,4),
                         addr=rd(b,o+12,4), off=rd(b,o+16,4), size=rd(b,o+20,4),
                         link=rd(b,o+24,4), entsize=rd(b,o+36,4))
            self.sh.append(s)
        # A pxx EXECUTABLE carries program headers and NO section headers at
        # all, so this has to tolerate shnum == 0 rather than assume a .symtab.
        if shnum and shstrndx < shnum:
            st = self.sh[shstrndx]; strs = b[st['off']:st['off']+st['size']]
            for s in self.sh:
                s['sname'] = strs[s['name']:strs.index(b'\0', s['name'])].decode()
        else:
            for s in self.sh: s['sname'] = ''

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


_UNDEF_SEEN = {}
SYNTH_UNDEF = True   # off in linker-oracle mode: ld picks the number there

def undef_addr(name):
    """A synthetic address for an undefined symbol, so a relocation against an
    extern can still be applied and checked.

    EVERY 16-BIT FIELD IS DISTINCT AND NON-ZERO, deliberately. aarch64 splits an
    absolute address across MOVW_UABS_G0_NC/G1_NC/G2_NC/G3, one 16-bit chunk
    each; an address with a zero chunk, a repeated chunk, or a chunk equal to
    another symbol's would let a G0/G1 SWAP, a dropped write, or a
    wrong-symbol resolution pass. Same reason the C-ABI probe passes 11/22/33
    rather than 1/1/1: a value that collides with the failure value is a row
    that cannot fail.

    The addresses are stable per name within a run so two relocations against
    one symbol must agree."""
    if not SYNTH_UNDEF:
        return None
    if name in _UNDEF_SEEN:
        return _UNDEF_SEEN[name]
    i = len(_UNDEF_SEEN) + 1
    if i >= 0x0f00:
        return None          # ran out of distinct chunks; say so, do not wrap
    a = ((0x4000 + i) << 48) | ((0x3000 + i) << 32) | ((0x2000 + i) << 16) | (0x1000 + i)
    _UNDEF_SEEN[name] = a
    return a


def exe_text_off(xe):
    """File offset of the first executable PT_LOAD, and the vaddr it maps."""
    b = xe.b; w64 = xe.cls == 2
    phoff = rd(b, 0x20, 8) if w64 else rd(b, 0x1c, 4)
    phentsize = rd(b, 0x36 if w64 else 0x2a, 2)
    phnum = rd(b, 0x38 if w64 else 0x2c, 2)
    for i in range(phnum):
        o = phoff + i * phentsize
        if rd(b, o, 4) != 1: continue                   # PT_LOAD
        flags = rd(b, o + 4, 4) if w64 else rd(b, o + 24, 4)
        if not (flags & 0x1): continue                  # PF_X
        off = rd(b, o + 8, 8) if w64 else rd(b, o + 4, 4)
        va  = rd(b, o + 16, 8) if w64 else rd(b, o + 8, 4)
        return (off, va)
    return None


def exe_bytes(xe, xoff, va, n):
    off, base_va = xoff
    start = off + (va - base_va)
    return xe.b[start:start + n]


def _reloc_mask(e, sname, size):
    """Byte positions in a section that a relocation writes. They are the ONLY
    places the executable and the object are allowed to differ when the same
    bytes are loaded at a known address, because the executable has the
    resolved value baked in and the object has not."""
    m = bytearray(size)
    for r in e.relocs(sname):
        o = r['off']
        for i in range(o, min(o + 8, size)): m[i] = 1
    return m


def content_regions(e, xe):
    """Where each of the object's PROGBITS sections actually landed, found from
    the executable's own loadable segments and its section CONTENT.

    THIS EXISTS BECAUSE A pxx EXECUTABLE SPLITS ONE .data ACROSS TWO SEGMENTS
    AND AN OBJECT CANNOT. Measured 2026-09-22 on the first aarch64 object: the
    executable loads .data[0x20:] read-only at 0x4c0000 and .data[0x00:0x20]
    writable at 0x4d3270, so references into the SAME section resolve against
    two bases 0x13290 apart. solve_bases's vote split 265 to 7 and the mode
    refused -- correctly, and uninformatively. The OBJECT is fine: a linker
    placing .data contiguously resolves every one of those sites consistently.
    It is the executable that has a layout an object cannot express.

    THE TWO BASES ARE ATTESTED SEPARATELY, AND NEITHER BY THE RELOCATIONS. The
    danger in any multi-base model is choosing the base per site TO MAKE THE
    SITE MATCH, because fitting always agrees. So:

      the PRINCIPAL region is found by sliding the segment's bytes along the
      section's and taking the offset with the fewest mismatches, over probe
      positions where the SEGMENT byte is nonzero. This is only usable because
      the separation is not marginal, and the margin is measured rather than
      hoped for: aarch64 scored 2 mismatches of 512 at the right offset and
      486 at the runner-up, x86-64 7 against 480. The rule demands <=10% at the
      best and >=50% at the second, which those clear by an order of magnitude.

      the PREFIX region -- section bytes before the principal region's start --
      is attested by its base being EXACTLY the vaddr of a writable PT_LOAD,
      which is a number in the program headers and not one this harness can
      fit. It applies only when exactly one such segment is a candidate.

    THE MATCH TOLERATES MISMATCHES, AND HAS TO. An exact compare found nothing
    at all, which reads as "these layouts do not correspond" and is wrong.
    Some .data words differ because the executable has resolved pointers where
    the object has zeros; others differ because the executable's build-time
    writer fills slots an object leaves for runtime initialisation. THE
    CONTROL FOR THAT CLAIM IS x86-64, whose object links with GNU ld and whose
    linked binary runs: it shows the same unrelocated differences (83 bytes in
    the read-only region, 10 in the writable one), so they are normal and not
    a missing relocation on aarch64. A known-good target is what separates
    "this writer is incomplete" from "this comparison is looking at the wrong
    thing", and nothing else available here does.

    Returns {shndx: [(lo, hi, base), ...]}, most specific first."""
    out = {}
    b = bytes(xe.b)
    phoff = rd(b, 0x20, 8) if xe.cls == 2 else rd(b, 0x1c, 4)
    phent = rd(b, 0x36 if xe.cls == 2 else 0x2a, 2)
    phnum = rd(b, 0x38 if xe.cls == 2 else 0x2c, 2)
    segs = []
    for i in range(phnum):
        o = phoff + i * phent
        if rd(b, o, 4) != 1: continue                       # PT_LOAD
        if xe.cls == 2:
            fl, off, va, fsz = (rd(b, o+4, 4), rd(b, o+8, 8),
                                rd(b, o+16, 8), rd(b, o+32, 8))
        else:
            fl, off, va, fsz = (rd(b, o+24, 4), rd(b, o+4, 4),
                                rd(b, o+8, 4), rd(b, o+16, 4))
        if fsz: segs.append((off, va, fsz, fl))
    for k, sh in enumerate(e.sh):
        if sh['type'] != 1 or not (sh['flags'] & 0x2):      # PROGBITS + ALLOC
            continue
        # NOT the executable section. Its base already has an independent
        # attestation -- a defined FUNC symbol matched BY NAME against the
        # executable's map -- so a content search adds no evidence, and the
        # search is quadratic: .text is 772 KB against a 512-position probe,
        # which is 400M byte comparisons and took this function from under a
        # second to over two minutes.
        if sh['flags'] & 0x4:                               # SHF_EXECINSTR
            continue
        body = bytes(e.data(sh))
        if not body: continue
        best = None
        for off, va, fsz, fl in segs:
            seg = b[off:off+fsz]
            if not seg or len(seg) > len(body): continue
            probe = [j for j in range(len(seg)) if seg[j]]
            if len(probe) < 32: continue        # too little signal to place it
            if len(probe) > 512: probe = probe[::len(probe)//512][:512]
            sc = sorted((sum(1 for j in probe if body[K+j] != seg[j]), K)
                        for K in range(len(body) - len(seg) + 1))
            if sc[0][0] > 0.10 * len(probe): continue
            if len(sc) > 1 and sc[1][0] < 0.50 * len(probe): continue
            cand = (len(seg), sc[0][1], va - sc[0][1], va, fsz)
            if best is None or cand[0] > best[0]: best = cand
        if best is None: continue
        _, K, base, va, fsz = best
        regs = [(K, K + fsz, base)]
        if K > 0:
            # The bytes before the principal region have to live somewhere, and
            # in a pxx executable that is the writable segment. Accept it only
            # if exactly one writable PT_LOAD can hold them: its vaddr is then
            # the prefix's base, taken from the program headers rather than
            # fitted to anything.
            w = [sg for sg in segs
                 if (sg[3] & 0x2) and sg[2] >= K and sg[1] != va]
            if len(w) == 1:
                regs.append((0, K, w[0][1]))
        out[k] = sorted(regs, key=lambda r: r[1]-r[0])
    return out


def base_at(base_of, regions, shndx, off):
    """The base a reference at `off` inside section `shndx` resolves against.
    One region (or none recorded) is the ordinary case and behaves exactly as
    the plain dict did."""
    rs = (regions or {}).get(shndx)
    if rs and len(rs) > 1:
        for lo, hi, bs in rs:                                # most specific first
            if lo <= off < hi: return bs
    return base_of.get(shndx)


# THE VOTE'S MODEL IS "THE EXECUTABLE HOLDS THE RESOLVED ADDRESS AT THIS
# SITE", AND THAT IS ONLY TRUE FOR AN ABSOLUTE DATA WORD. Measured 2026-09-22
# on the movz/movk probe: a MOVW site's four bytes are an INSTRUCTION, so
# reading them as an address contributed a junk vote of 0xd2827fb0, the vote
# became three-way, and solve_bases refused with "the layouts differ" -- an
# honest message about the wrong thing. PC-relative and instruction-field
# relocations are excluded for the same reason. Keeping this as an explicit
# allowlist rather than a denylist means a new relocation type is silently
# ignored by the vote instead of silently corrupting it.
VOTE_ABSOLUTE = {
    62:  {1, 11},          # EM_X86_64: R_X86_64_64, _32S
    3:   {1},              # EM_386:    R_386_32
    243: {1},              # EM_RISCV:  R_RISCV_32
    94:  {1},              # EM_XTENSA: R_XTENSA_32
    183: {257, 258},       # EM_AARCH64: ABS64 (low word), ABS32
}


def solve_bases(e, syms, xe, xoff, text, regions=None):
    """Where each of the object's sections landed in the executable, derived
    from the executable's own bytes rather than from anything pxx reports.

    For each relocation naming a section other than .text, the executable
    already holds the RESOLVED word at that site, so
    base = resolved - (sym.value + addend). Every relocation naming one section
    is an independent vote. UNANIMITY IS THE CONTROL: a single wrong addend is
    a minority vote rather than a shifted base, and a genuinely split vote
    means the two builds do not share a layout and this oracle does not apply.

    .text's own base comes from a defined FUNC symbol, which needs no
    relocation and so cannot be circular."""
    from collections import Counter
    ti = e.sh.index(text)
    tbase = None
    for s in syms:
        if s['shndx'] == ti and s['name'] and s['value']:
            for xs in xe.symbols() if xe.sec('.symtab') else []:
                if xs['name'] == s['name']:
                    tbase = xs['value'] - s['value']; break
            if tbase is not None: break
    if tbase is None:
        tbase = _tbase_from_map(xe.path + '.map', syms, ti)
    if tbase is None: return None, {}
    et = exe_bytes(xe, xoff, tbase, e.sec('.text')['size'])
    if len(et) < e.sec('.text')['size']: return None, {}
    votes = {}
    absset = VOTE_ABSOLUTE.get(e.machine, set())
    for r in e.relocs('text'):
        s = syms[r['sym']]
        if s['shndx'] in (0, ti): continue
        if r['type'] not in absset: continue
        try: have = struct.unpack_from('<I', et, r['off'])[0]
        except Exception: continue
        votes.setdefault(s['shndx'], Counter())[have - (s['value'] + (r['addend'] or 0))] += 1
    base = {ti: tbase}
    for k, c in votes.items():
        top = c.most_common(2)
        attested = {r[2] for r in (regions or {}).get(k, [])}
        if len(top) > 1 and top[1][1] > top[0][1] * 0.02:
            # A split vote is two layouts -- which is a REFUSAL unless every
            # value the vote produced is a base the executable's own segments
            # attest by content. Then it is not two layouts, it is one section
            # the executable loaded in two pieces, and content_regions already
            # fixed which offsets belong to which piece.
            if len(attested) > 1 and set(c) <= attested:
                base[k] = max(regions[k], key=lambda r: r[1]-r[0])[2]
                continue
            return None, votes
        base[k] = top[0][0]
    return base, votes


def _tbase_from_map(mappath, syms, ti):
    """pxx writes a .map beside every executable and its executables carry NO
    section headers, so this is the normal path rather than a fallback.

    It matches a FUNC symbol the object defines against the same name in the
    map. Two independent names must agree, or the layouts do not correspond
    and saying so is the answer -- one name can be right by coincidence in a
    way two cannot."""
    if not os.path.exists(mappath): return None
    m = {}
    for ln in open(mappath):
        p = ln.split()
        if len(p) == 2 and p[0].startswith('0x'):
            try: m[p[1]] = int(p[0], 16)
            except ValueError: pass
    cands = []
    for s in syms:
        if s['shndx'] == ti and s['name'] in m and s['value']:
            cands.append(m[s['name']] - s['value'])
        if len(cands) >= 3: break
    if len(cands) < 2 or len(set(cands)) != 1: return None
    return cands[0]


def runtime_witness(exe, runner, e, syms):
    """Section bases as the RUNNING program reports them.

    THIS IS THE ONLY CHANNEL THAT CAN SEE A UNIFORM OFFSET ERROR. Where no
    linker exists the harness derives a section's base by majority vote over
    the relocations naming it, and a base derived FROM the relocations and then
    used to CHECK them agrees by construction: if every reference to one
    section is wrong by the same N, the vote lands on true_base - N, all votes
    agree, and the byte comparison is clean. Unanimity is blind to it BECAUSE
    it is unanimous -- the minority is the only channel carrying signal, so a
    zero minority is zero signal, not maximum confidence.

    The probe prints &g and msg. Subtracting the OBJECT's own symbol values
    from the addresses the program printed yields a base that no relocation
    arithmetic here produced, so a uniform shift becomes a mismatch.
    (frankuser, 2026-09-22.)

    A FIFTH CONTROL WAS PROPOSED AND IS REDUNDANT -- MEASURED, NOT ARGUED.
    The symmetric case is an object symbol whose st_value is wrong: that moves
    the WITNESS rather than the vote, where the uniform-shift control moves the
    vote rather than the witness. Measured 2026-09-22 on riscv32 by bumping
    g.st_value 0x860c -> 0x8610 in a copy of the object: the harness already
    exits 1, with `BROKEN -- no runtime witness (two symbols in .bss imply
    different bases ['0x81202b8', '0x81202b4'])`. It is caught by a guard
    NEITHER of us predicted -- not the vote-versus-witness comparison, but the
    witness's own internal consistency, because .bss holds two witnessed
    symbols and a per-symbol error makes them disagree with EACH OTHER before
    anything is compared to the vote. Note what that implies and what would
    retire this paragraph: the cover is a property of the PROBE, not of the
    harness. It holds only while some section carries two or more witnessed
    symbols. Add the fifth control if the probe is ever reduced to one witness
    per section -- and re-measure rather than trusting this note."""
    cmd = ([runner] if runner else []) + [exe]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception as ex:
        return None, f'could not run: {ex}'
    parts = r.stdout.split()
    if len(parts) < 4 or not parts[1].startswith('0x'):
        return None, f'unexpected output {r.stdout.strip()[:40]!r}'
    if parts[0] != '42':
        return None, f'the probe computed {parts[0]!r}, not 42'
    out = {}
    for nm, txt in (('g', parts[1]), ('msg', parts[2])):
        sym = next((x for x in syms if x['name'] == nm), None)
        if sym is None: return None, f'no symbol {nm} in the object'
        out.setdefault(sym['shndx'], []).append(int(txt, 16) - sym['value'])
    # A string literal carries no symbol, so it is located by CONTENT. It must
    # occur EXACTLY ONCE or the offset is ambiguous, and an ambiguous witness
    # is worse than none -- it would pick one occurrence and look definite.
    needle = b'pxx-reloc-rodata-witness-do-not-duplicate'
    for i in alloc_sections(e):
        blob = bytes(e.data(e.sh[i]))
        n = blob.count(needle)
        if n == 1:
            out.setdefault(i, []).append(int(parts[3], 16) - blob.index(needle))
        elif n > 1:
            return None, (f'the .rodata witness string occurs {n} times in '
                          f'{e.sh[i]["sname"]}, so its offset is ambiguous')
    bases = {}
    for shndx, vals in out.items():
        if len(set(vals)) != 1:
            return None, (f'two symbols in {e.sh[shndx]["sname"]} imply different '
                          f'bases {[hex(v) for v in set(vals)]}')
        bases[shndx] = vals[0]
    return bases, None


def alloc_sections(e):
    """Every SHF_ALLOC section with content, in file order.

    NOT a hardcoded .text/.data/.bss list, and the reason is measured: the
    first version of this harness seeded exactly those three and reported 264
    riscv32 relocations as naming UNDEFINED symbols that only a linker could
    place. They were nothing of the kind -- they named `.rodata`, an ordinary
    defined section the list had simply left out, and the harness described its
    own omission as a property of the object. A census that enumerates a
    hardcoded set answers honestly about that set and says nothing about what
    it left out. Ask the ELF what sections it has."""
    SHF_ALLOC = 0x2
    out = []
    for i, sh in enumerate(e.sh):
        if sh['type'] in (1, 8) and (sh['flags'] & SHF_ALLOC):
            out.append(i)
    return out


def apply_relocs(e, secname, secdata, base_of, sec_va, syms, unhandled,
                 regions=None):
    for r in e.relocs(secname):
        _apply_one(e, r, secdata, base_of, sec_va, syms, unhandled, regions)


def _apply_one(e, r, secdata, base_of, sec_va, syms, unhandled, regions=None):
    """Patch `secdata` in place. Arithmetic straight from each psABI.

    An IN-PLACE addend (SHT_REL) is read out of the bytes the relocation
    covers, which is what makes i386 different from x86-64 rather than merely
    smaller."""
    s = syms[r['sym']]
    b_ = base_at(base_of, regions, s['shndx'], s['value'] + (r['addend'] or 0))
    if b_ is None:
        # SHN_UNDEF. A LINKER'S ONLY CONTRIBUTION HERE IS CHOOSING THE NUMBER,
        # so the harness chooses it instead and checks the bytes encode THAT.
        # Skipping these instead would have excluded exactly the class this
        # harness exists for on aarch64: pxx reaches an EXTERN through a
        # movz/movk pair, so MOVW_UABS_G0_NC/G1_NC are relocations against
        # UNDEFINED symbols, and a run that skipped them would report a green
        # over the resolvable majority while never touching the subject.
        # (frankuser, 2026-09-22 -- caught before the aarch64 writer existed.)
        b_ = undef_addr(s['name'])
        if b_ is None:
            unhandled.setdefault('_undef', 0)
            unhandled['_undef'] += 1
            return
        unhandled.setdefault('_synth', 0)
        unhandled['_synth'] += 1
        s = dict(s, value=0)
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
        elif r['type'] == 258:                   # R_AARCH64_ABS32
            # FOUR BYTES ON A 64-BIT TARGET, and writing eight here would
            # silently destroy the branch that follows the literal. pxx's
            # aarch64 backend materialises a .bss address with `ldr w0,[pc+8]`
            # over a 4-byte literal, so this is the COMMONEST relocation in an
            # aarch64 object (1077 of 1350 in the probe) and it was not in the
            # first version of this arm, which was written from the psABI
            # before the writer existed and expected instruction fields.
            v = S + A
            if v >= 2**32:
                unhandled['aarch64:ABS32-overflow'] = \
                    unhandled.get('aarch64:ABS32-overflow', 0) + 1
            struct.pack_into('<I', secdata, r['off'], v & 0xffffffff)
        elif 263 <= r['type'] <= 269:
            # G0=263 G0_NC=264 G1=265 G1_NC=266 G2=267 G2_NC=268 G3=269.
            # _NC ALTERNATES WITH THE CHECKED FORM, so the naive reading
            # "263,264,265,266 are G0..G3" is off by a factor of two and lands
            # on the checked variant of the same group -- which is exactly the
            # table this harness and the writer both held until clang's own
            # object was read for the names (2026-09-22).
            shift = {263: 0, 264: 0, 265: 16, 266: 16,
                     267: 32, 268: 32, 269: 48}[r['type']]
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


def clang_movw_oracle():
    """An EXTERNAL check on the one piece of arithmetic nothing else reaches.

    clang cannot EMIT R_AARCH64_MOVW_UABS_G0_NC -- it materialises an address
    with adrp/add and a CALL26, measured on this box with clang 21.1.8 -- so it
    is no oracle for whether pxx should use MOVW at all. It CAN assemble the
    instruction, and that is a different and sufficient question: given a value,
    which bits of the instruction word does it go in? That is the half of the
    MOVW relocation this harness computes from one reading of the psABI, and
    the ld calibration does not touch it, because ld here has no aarch64
    emulation.

    It asks clang for `movz x16,#0x1234` and `movk x16,#0x5678,lsl #16`, and
    for the two ZERO-immediate forms beside them, then applies this harness's
    own MOVW arithmetic to the zero forms and requires the results to be
    clang's non-zero words BYTE FOR BYTE. A value in the wrong field, a wrong
    shift, or a clobbered register number all fail it.

    A SECOND THING FALLS OUT AND IT IS WORTH THE LINE: clang's encoding of
    `movz x16,#0` is 0xd2800010 and of `movk x16,#0,lsl #16` is 0xf2a00010,
    which are the exact literals EmitExternalCallA64 emits by hand in
    symtab.inc. The backend's hand-written encodings are confirmed by an
    external assembler, which no test here did before.

    Returns (ok, detail) or (None, why) when clang cannot target aarch64."""
    import shutil
    cc = shutil.which('clang') or shutil.which('clang-21')
    if not cc: return None, 'no clang on this box'
    d = tempfile.mkdtemp(prefix='movwchk-')
    src = os.path.join(d, 'm.s'); obj = os.path.join(d, 'm.o')
    open(src, 'w').write('movz x16, #0x1234\n'
                         'movk x16, #0x5678, lsl #16\n'
                         'movz x16, #0\n'
                         'movk x16, #0, lsl #16\n')
    r = subprocess.run([cc, '--target=aarch64-linux-gnu', '-c', src, '-o', obj],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, f'clang cannot target aarch64 here: {r.stderr.strip()[:60]}'
    e = Elf(obj); b = bytes(e.data(e.sec('.text')))
    if len(b) < 16: return None, 'clang emitted an unexpected .text'
    w = [struct.unpack_from('<I', b, i)[0] for i in range(0, 16, 4)]
    V = 0x56781234
    rows = []
    for insn, shift, want in ((w[2], 0, w[0]), (w[3], 16, w[1])):
        got = (insn & ~(0xffff << 5)) | (((V >> shift) & 0xffff) << 5)
        rows.append((shift, got, want))
    ok = all(g == wv for _, g, wv in rows)
    detail = '  '.join(f'G{ "0" if sh==0 else "1" }:{g:#010x}vs{wv:#010x}'
                       for sh, g, wv in rows)
    pxx_movz, pxx_movk = 0xd2800010, 0xf2a00010
    same = (w[2] == pxx_movz and w[3] == pxx_movk)
    return ok, (detail + ('  [and clang agrees with EmitExternalCallA64\'s own '
                          'hand-written movz/movk words]' if same else
                          '  [NOTE: clang\'s zero forms differ from the '
                          'literals in symtab.inc]'))


def clang_movw_entries():
    """What a MOVW_UABS GROUP looks like when an external assembler emits one.

    clang_movw_oracle above answers "which bits does the value go in". This
    answers the OTHER half, which that one explicitly leaves open: which
    relocation ENTRIES describe a movz/movk sequence -- their types, their
    offsets relative to each other, and their addends. Entries need no linker,
    which is what makes this reachable on a box with no aarch64 ld.

    THE OBSTACLE AND THE WAY ROUND IT (frankuser's lead, 2026-09-22, and it
    held only for the second half). At the default code model clang
    materialises an address with adrp/add, so its entries are ADR_PREL_PG_HI21
    and ADD_ABS_LO12_NC and are not comparable to pxx's by construction.
    `-fno-pic -mcmodel=large` was the proposed fix. Measured: it does NOT work
    for a CALL -- clang still emits `bl` with an R_AARCH64_CALL26 and leaves
    range to a linker veneer -- and it DOES work for a DATA address, which is
    the shape pxx's GOT-slot reference actually is. So the oracle exists, and
    the source that produces it is `&extern_var`, not a call.

    Returns a list of (offset, type, addend) or None."""
    import shutil
    cc = shutil.which('clang') or shutil.which('clang-21')
    if not cc: return None
    d = tempfile.mkdtemp(prefix='movwent-')
    src, obj = os.path.join(d, 'a.c'), os.path.join(d, 'a.o')
    open(src, 'w').write('extern int ext_var;\nint *get(void){ return &ext_var; }\n')
    r = subprocess.run([cc, '--target=aarch64-linux-gnu', '-fno-pic',
                        '-mcmodel=large', '-c', src, '-o', obj],
                       capture_output=True, text=True)
    if r.returncode != 0: return None
    e = Elf(obj)
    return [(x['off'], x['type'], x['addend'] or 0)
            for x in e.relocs('text') if 263 <= x['type'] <= 269]


def movw_value_check(pxx, pxxflag, src, work, tname):
    """The external-call arm, end to end, on a source that REACHES it.

    Two questions and two different answers, and conflating them is how this
    would become a tautology:

      SHAPE, against clang -- an external assembler. A MOVW_UABS group is one
      entry per instruction, four bytes apart, types ascending G0_NC, G1_NC
      (clang's own group runs on to G2_NC and G3 for a full 64-bit address),
      and THE SAME ADDEND ON EVERY ENTRY. That last one is the invariant worth
      having: get the addend right on one entry and wrong on the other and the
      link still succeeds, and the program calls a plausible address in the
      wrong 64 KiB.

      VALUE, against pxx's own PatchDynCallSites -- and this is NOT an
      independent oracle, it is a cross-check between two implementations
      inside one compiler. It is worth running and worth labelling: the
      executable's patcher computes the slot address by a completely different
      route from this harness's psABI arithmetic, so agreement is evidence,
      and it is not the evidence a linker would give.

    THE EXECUTABLE HERE IS NEVER RUN. pxx's binary for this source is
    dynamically linked and this box has no /lib/ld-linux-aarch64.so.1, so it is
    read for its bytes only -- no witness, and none is claimed.

    PXX EMITS TWO ENTRIES WHERE CLANG EMITS FOUR, AND THAT IS A REAL LIMIT
    RATHER THAN A DEFECT. G0_NC + G1_NC cover the low 32 bits of the GOT slot
    address, which is correct while .data lands below 4 GiB and is what a
    -no-pie static link does. It is worth knowing that the _NC suffix means NO
    CHECK: above 4 GiB this truncates SILENTLY, where the ABS32 relocation the
    same writer emits for a .bss reference would refuse. Noted, not fixed --
    there are only two instructions to hang relocations on."""
    obj = os.path.join(work, 'movw.o'); exe = os.path.join(work, 'movw.elf')
    for out, extra in ((obj, ['--emit-obj']), (exe, [])):
        r = subprocess.run([pxx] + pxxflag.split() + extra + [src, out],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f'   movw arm: SKIP -- pxx refused: '
                  f'{(r.stdout + r.stderr).strip().splitlines()[-1][:90]}')
            return 0
    e = Elf(obj); syms = e.symbols()
    grp = [r for r in e.relocs('text') if 263 <= r['type'] <= 269]
    if not grp:
        print('   movw arm: BROKEN -- the probe written to reach this arm '
              'produced no movz/movk relocation')
        return 1
    grp.sort(key=lambda r: r['off'])
    ok = True
    for i in range(0, len(grp), 2):
        a, b = grp[i], grp[i+1] if i+1 < len(grp) else None
        if b is None or b['off'] != a['off'] + 4 or \
           a['type'] != 264 or b['type'] != 266 or \
           (a['addend'] or 0) != (b['addend'] or 0):
            ok = False
    ce = clang_movw_entries()
    if ce:
        ce.sort()
        cstep = all(ce[j+1][0] == ce[j][0] + 4 for j in range(len(ce)-1))
        csame = len({t[2] for t in ce}) == 1
        ctypes = [t[1] for t in ce]
        print(f'   movw shape oracle: clang group = {len(ce)} entries, '
              f'types {ctypes}, 4-byte step {cstep}, one addend {csame}')
        if not (cstep and csame and ctypes[:2] == [264, 266]):
            print('   movw arm: BROKEN -- clang\'s own group does not have the '
                  'shape this check assumes; the assumption is what is wrong')
            return 1
    else:
        print('   movw shape oracle: SKIP -- clang cannot emit a MOVW group here')
    print(f'   movw shape: pxx group = {len(grp)} entries, '
          f'{"MATCHES clang\'s invariants" if ok else "VIOLATES them"} '
          f'(pairwise G0_NC/G1_NC, +4 apart, equal addends)')
    if not ok:
        return 1
    # COHERENCE, and it replaces a comparison that was never valid. The first
    # version resolved the pair here and compared with the bytes pxx's own
    # PatchDynCallSites produced in the executable. It DIFFERS, and the object
    # is right: measured 2026-09-22, the executable places its GOT slots in the
    # writable segment while the object carries them inside .data at their own
    # offsets, so the two builds legitimately disagree about WHERE the slot is.
    # Comparing them tests the correspondence assumption, not the writer, and
    # reporting that as a relocation defect is the mistake this whole harness
    # exists to avoid.
    #
    # What IS checkable from the object alone is the invariant the two-
    # relocation design rests on: the movz/movk addend names a .data offset
    # where a real GOT slot lives -- an ABS64 against an UNDEFINED symbol. A
    # wrong addend points into .data at no slot at all, or at another
    # extern's, and this sees both. With two externs it also sees every site
    # collapsing onto one slot.
    slots = {r['off']: syms[r['sym']]
             for r in e.relocs('data')
             if syms[r['sym']]['shndx'] == 0}
    bad = []
    seen = {}
    for i in range(0, len(grp), 2):
        a = grp[i]; ad = a['addend'] or 0
        tgt = slots.get(ad)
        if tgt is None:
            bad.append(f'{a["off"]:#x} -> .data+{ad:#x} where no GOT slot is defined')
        else:
            seen.setdefault(tgt['name'], []).append(a['off'])
    if bad:
        print('   movw coherence: BROKEN -- ' + '; '.join(bad))
        return 1
    print(f'   movw coherence: every group\'s addend names a real GOT slot '
          f'{dict((k, len(v)) for k, v in seen.items())} -- each slot an ABS64 '
          f'against an UNDEFINED symbol, which is the invariant the two-'
          f'relocation design rests on')
    if len(slots) > 1 and len(seen) < 2:
        print('   movw coherence: BROKEN -- the object defines '
              f'{len(slots)} extern slots and every call site points at '
              f'{len(seen)}; the sites have collapsed onto one slot')
        return 1
    # ITS OWN POSITIVE CONTROL, because a coherence check over a correct object
    # is exactly the shape that passes without being able to fail. Two
    # perturbations, both drawn from how this writer would really go wrong: an
    # addend off by one slot, and every site pointing at the same slot.
    def coherent(gs):
        sn = {}
        for j in range(0, len(gs), 2):
            t = slots.get(gs[j]['addend'] or 0)
            if t is None: return False
            sn.setdefault(t['name'], 0)
        return not (len(slots) > 1 and len(sn) < 2)
    off1 = [dict(r, addend=(r['addend'] or 0) + 8) if j < 2 else r
            for j, r in enumerate(grp)]
    allone = [dict(r, addend=sorted(slots)[0]) for r in grp]
    ctl = [('addend off by one slot', coherent(off1)),
           ('every site one slot', coherent(allone))]
    if any(ok for _, ok in ctl):
        print('   movw coherence: BROKEN -- a control it must reject was '
              f'accepted: {[n for n, ok in ctl if ok]}')
        return 1
    print(f'   movw coherence controls: {len(ctl)} of {len(ctl)} rejected '
          f'(addend off by one slot; every site on one slot)')
    return 0


def uniform_shift_control(e, text, base, wit, syms, xe, xoff, tname,
                          regions=None):
    """Prove the uniform-offset hole is real AND that the witness closes it."""
    from collections import Counter
    ti = e.sh.index(text)
    target = next((k for k in wit if k != ti and k in base), None)
    if target is None:
        print('   CONTROL uniform shift    -> BROKEN: no witnessed section to shift')
        return False
    N = 4
    tb2 = e.data(text)
    votes = Counter()
    et = exe_bytes(xe, xoff, base[ti], e.sec('.text')['size'])
    for r in e.relocs('text'):
        s = syms[r['sym']]
        rr = dict(r, addend=(r['addend'] or 0) + N) if s['shndx'] == target else r
        if s['shndx'] == target and r['type'] in VOTE_ABSOLUTE.get(e.machine, set()):
            have = struct.unpack_from('<I', et, r['off'])[0]
            votes[have - (s['value'] + (rr['addend'] or 0))] += 1
    if not votes:
        print('   CONTROL uniform shift    -> BROKEN: no relocation names that section')
        return False
    shifted = dict(base); shifted[target] = votes.most_common(1)[0][0]
    unh = {}
    for r in e.relocs('text'):
        s = syms[r['sym']]
        rr = dict(r, addend=(r['addend'] or 0) + N) if s['shndx'] == target else r
        _apply_one(e, rr, tb2, shifted, base[ti], syms, unh, regions)
    bytes_blind = bytes(tb2) == et
    witness_sees = shifted[target] != wit[target]
    nm = e.sh[target]['sname']
    print(f'   CONTROL uniform shift    -> bytes {"MISS it (as predicted)" if bytes_blind else "caught it"}'
          f', witness {"CATCHES it" if witness_sees else "MISSES IT"}   [{nm} +{N}]')
    if not witness_sees:
        print(f'   CONTROLS: BROKEN -- a uniform +{N} on every {nm} reference was '
              f'invisible to BOTH the byte comparison and the witness')
        return False
    if not bytes_blind:
        # Not a failure: it means the vote did not fully absorb the shift here,
        # so the byte comparison happens to catch it too. Worth printing,
        # because it means this target is less exposed than the general case.
        pass
    return True


def control_suite(e, text, base, addrs, syms, theirs, tname, regions=None):
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
    # THE BASELINE MUST AGREE BEFORE A PERTURBATION MEANS ANYTHING. Measured
    # 2026-09-22 on the first aarch64 run: these three controls were passed a
    # single base per section while the executable loads .data in two pieces,
    # so the UNPERTURBED resolution already differed and every control
    # reddened no matter what it did -- "3 of 3 controls reddened it" over a
    # comparison that could not have been green. A control that cannot come
    # out STILL AGREES is not a control, and the assert is one line.
    tb0 = e.data(text); unh0 = {}
    for r in e.relocs('text'):
        _apply_one(e, r, tb0, base, addrs['.text'], syms, unh0, regions)
    if bytes(tb0) != theirs:
        print('   CONTROLS: BROKEN -- the UNPERTURBED resolution already '
              'differs, so every perturbation reddens vacuously')
        return False
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
            _apply_one(e, rr, tb2, base, addrs['.text'], syms, unh, regions)
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
    # name:      (pxx flag,          gcc flag or None if unlinkable here,
    #             runner for the executable-oracle witness or None if native)
    'x86_64':   ('',                 '-no-pie',       None),
    'i386':     ('--target=i386',    '-m32 -no-pie',  None),
    'riscv32':  ('--target=riscv32', None,            'qemu-riscv32'),
    'xtensa':   ('--target=xtensa',  None,            None),
    'aarch64':  ('--target=aarch64', None,            'qemu-aarch64'),
    'arm32':    ('--target=arm32',   None,            'qemu-arm'),
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
    pxxflag, gccflag, runner = TARGETS[tname]
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
        # EXECUTABLE-ORACLE MODE, for the targets with no linker on this box.
        #
        # The oracle chain is: qemu proves the EXECUTABLE (the per-target tiers
        # run these), and the executable proves the OBJECT. It works only where
        # the two builds share a layout, which is a property to MEASURE and not
        # to assume -- on x86-64 they do not (296788 of 328517 bytes differ,
        # because an object has no _start and the export surface differs) and
        # on riscv32 they correspond exactly. So the mode establishes the
        # correspondence first, from defined symbols, and refuses if it cannot.
        exe = os.path.join(work, 'exe')
        er = subprocess.run([pxx] + pxxflag.split() + [src, exe],
                            capture_output=True, text=True)
        if er.returncode != 0:
            print(f'reloc-resolve[{tname}]: SKIP -- pxx cannot build an executable here')
            return 0
        xe = Elf(exe)
        # Section bases come from the EXECUTABLE, by majority vote over the
        # relocations that name each section. Unanimity is the control: one
        # wrong addend shows up as a minority vote rather than shifting the
        # base, and a split vote means the layouts do NOT correspond.
        xoff = exe_text_off(xe)
        if xoff is None:
            print(f'reloc-resolve[{tname}]: SKIP -- no loadable segment found in the executable')
            return 0
        regions = content_regions(e, xe)
        base, votes = solve_bases(e, syms, xe, xoff, text, regions)
        if base is None:
            print(f'reloc-resolve[{tname}]: SKIP -- the object and the executable do '
                  f'not share a layout here, so the executable cannot be the oracle')
            return 0
        # THE WITNESS RUNS BEFORE THE COMPARISON AND CAN VETO IT. Without it
        # the vote is checked against the relocations it was derived from.
        wit, why = runtime_witness(exe, runner, e, syms)
        if wit is None:
            print(f'reloc-resolve[{tname}]: BROKEN -- no runtime witness for the '
                  f'section bases ({why}), so a UNIFORM offset error in every '
                  f'reference to a section would pass unanimously')
            return 1
        for k, c in sorted(votes.items()):
            top = c.most_common(2)
            extra = (f', runner-up {top[1][0]:#x} x{top[1][1]}' if len(top) > 1
                     else ' (unanimous)')
            w = wit.get(k)
            if w is None:
                mark = 'NO WITNESS'
            elif w == top[0][0]:
                mark = 'witness agrees'
            else:
                mark = f'WITNESS SAYS {w:#x}'
            print(f'   base {e.sh[k]["sname"]:<14} {top[0][0]:#x}  '
                  f'{top[0][1]} votes{extra}  [{mark}]')
            if len(regions.get(k, [])) > 1:
                print('       ' + e.sh[k]['sname'] + ' is loaded in '
                      f'{len(regions[k])} pieces by this executable, each '
                      'located by CONTENT: ' + ', '.join(
                          f'[{lo:#x},{hi:#x}) -> {bs:#x}'
                          for lo, hi, bs in regions[k]))
        bad = [e.sh[k]['sname'] for k, v in wit.items()
               if k in base and base[k] != v]
        if bad:
            print(f'reloc-resolve[{tname}]: DIFFER -- the vote-derived base '
                  f'disagrees with the running program for {bad}. That is the '
                  f'signature of a UNIFORM offset error, which the byte '
                  f'comparison cannot see.')
            return 1
        unwitnessed = [e.sh[k]['sname'] for k in votes if k not in wit]
        if unwitnessed:
            print(f'   NOTE: {unwitnessed} have no runtime witness -- their bases '
                  f'rest on the vote alone and a uniform shift there is invisible')
        unh = {}
        tb = e.data(text)
        apply_relocs(e, 'text', tb, base, base[e.sh.index(text)], syms, unh,
                     regions)
        undef = unh.pop('_undef', 0); synth = unh.pop('_synth', 0)
        if unh:
            print(f'reloc-resolve[{tname}]: BROKEN -- unhandled relocation types {unh}')
            return 1
        theirs = exe_bytes(xe, xoff, base[e.sh.index(text)], len(tb))
        diff = [i for i in range(len(tb)) if tb[i] != theirs[i]]
        if diff:
            print(f'reloc-resolve[{tname}]: DIFFER -- {len(diff)} of {len(tb)} bytes '
                  f'disagree with pxx\'s own executable')
            for i in diff[:6]:
                print(f'   off={i:#x} harness={tb[i]:02x} exe={theirs[i]:02x}')
            return 1
        if not control_suite(e, text, base, {'.text': base[e.sh.index(text)]},
                             syms, theirs, tname, regions):
            return 1
        # THE FOURTH CONTROL, and it is the one the other three cannot make:
        # shift EVERY relocation naming one section by the same amount. The
        # vote then derives a base shifted by exactly the same amount, the
        # bytes still match, and only the runtime witness disagrees. It
        # asserts BOTH halves -- that the byte comparison misses it, and that
        # the witness catches it -- because either half alone would let the
        # control pass for the wrong reason.
        if not uniform_shift_control(e, text, base, wit, syms, xe, xoff,
                                     tname, regions):
            return 1
        # WHICH ARMS ACTUALLY RAN. A verdict over 1355 relocations says nothing
        # about an arm none of them exercised, and the probe decides that, not
        # the target: measured 2026-09-22, this probe drives ZERO of aarch64's
        # movz/movk relocations, because pxx resolves printf from its own crtl
        # and emits no undefined symbol at all. Printing the census is what
        # stops the headline standing in for coverage it does not have.
        from collections import Counter as _C
        cen = _C(r['type'] for r in e.relocs('text'))
        print('   applied: ' + ', '.join(f'type {t} x{n}'
                                         for t, n in sorted(cen.items())))
        if e.machine == 183:
            ok, detail = clang_movw_oracle()
            if ok is None:
                print(f'   movw field oracle: SKIP -- {detail}')
            elif ok:
                print(f'   movw field oracle: clang AGREES -- {detail}')
            else:
                print(f'   movw field oracle: clang DISAGREES -- {detail}')
                return 1
            if not any(263 <= t <= 269 for t in cen):
                # The arm this probe cannot reach gets its OWN probe rather
                # than a caveat. A source that reaches it exists and is
                # checked here; saying "not covered" and stopping would leave
                # the newest part of the writer resting on an assertion.
                mp = os.path.join(os.path.dirname(os.path.dirname(
                        os.path.abspath(__file__))), 'test',
                        'reloc_movw_probe.c')
                if os.path.exists(mp):
                    print('   the movz/movk arm is unreached by this probe; '
                          'running test/reloc_movw_probe.c for it')
                    if movw_value_check(pxx, pxxflag, mp, work, tname):
                        return 1
                else:
                    print('   NOTE: this probe applied NO movz/movk '
                          'relocation, so the run above says nothing about '
                          'that arm; the clang row is the only evidence here')
        print(f'reloc-resolve[{tname}]: AGREE with pxx\'s own executable on {len(tb)} '
              f'bytes, {nrel} relocations; 4 of 4 controls reddened it, and every '
              f'section base has an independent runtime witness')
        if synth:
            print(f'   {synth} relocations named UNDEFINED symbols and were resolved at '
                  f'addresses THIS HARNESS chose, so those rows are pxx graded against '
                  f'pxx and cannot fail on value -- only on field placement')
        print(f'   oracle: the executable, which the {tname} tier runs under qemu. '
              f'This does NOT establish that a real linker agrees.')
        return 0

    # LINKER-ORACLE MODE. This is the calibration that licenses the mode above.
    global SYNTH_UNDEF
    SYNTH_UNDEF = False        # ld chooses the addresses in this mode
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
    # THE CONTROLS RUN BEFORE THE VERDICT IS PRINTED, and the verdict names
    # them. "0 differing bytes" is the twin of "0 of 1768 correct": total
    # failure is what an instrument prints when nothing works, and TOTAL
    # SUCCESS is what it prints when nothing RAN. The green here is
    # trustworthy because three perturbations redden it, not because it is
    # clean -- so a reader who sees only the number is reading the wrong half.
    if not control_suite(e, text, base, addrs, syms, theirs, tname):
        return 1
    print(f'reloc-resolve[{tname}]: AGREE with GNU ld on {len(tb)} bytes, '
          f'{nrel - undef} relocations ({undef} undefined, ld-only); '
          f'3 of 3 controls reddened it')
    # And the program has to RUN, because bytes agreeing with ld says nothing
    # about whether ld and pxx agreed about the right thing.
    rr = subprocess.run([exe], capture_output=True, text=True, timeout=120)
    print(f'   linked binary runs: rc={rr.returncode} out={rr.stdout.strip()[:40]!r}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
