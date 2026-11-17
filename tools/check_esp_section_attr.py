#!/usr/bin/env python3
"""__attribute__((section)) in a freestanding ESP object, read back.

Compiles test/c_esp_section_attr.c with --freestanding --emit-obj for esp32s3
and esp32c3 and checks with Espressif's binutils:
  - each named data section exists under exactly its name, with the right
    flags, and holds its variable's bytes (the app descriptor too, though
    nothing references it);
  - the .iram* functions live in .iram1.text and nowhere else, every xtensa
    l32r in them reads a literal INSIDE .iram1.text (no flash fetch before
    cache init), and they reach other code only through a relocation;
  - linked by GNU ld with an esp32s3.ld-shaped script (KEEP(.rodata_desc)
    first in DROM), the descriptor sits at the DROM start.
Exits 0, saying so, when a toolchain is absent.
usage: tools/check_esp_section_attr.py <compiler> <tmpdir>
feature-c-section-attribute-on-esp
"""
import glob
import os
import re
import struct
import subprocess
import sys

SRC = 'test/c_esp_section_attr.c'


def tool(arch):
    pat = {'xtensa': '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin',
           'riscv': '~/.espressif/tools/riscv32-esp-elf/*/riscv32-esp-elf/bin'}[arch]
    pre = {'xtensa': 'xtensa-esp32s3-elf-', 'riscv': 'riscv32-esp-elf-'}[arch]
    bins = sorted(glob.glob(os.path.expanduser(pat)))
    return bins[-1] + '/' + pre if bins else None


def run(*a):
    return subprocess.run(list(a), check=True, capture_output=True, text=True).stdout


def sections(b, obj):
    out = {}
    for line in run(b + 'readelf', '-SW', obj).splitlines():
        m = re.match(r'\s*\[\s*(\d+)\]\s+(\S+)\s+(\S+)\s+\S+\s+(\S+)\s+(\S+)\s+\S+\s+([A-Z]*)\s', line)
        if m:
            out.setdefault(m.group(2), []).append(
                (int(m.group(1)), int(m.group(4), 16), int(m.group(5), 16), m.group(6)))
    return out


def check(cc, tmp, arch, chip, fails):
    b = tool(arch)
    if not b:
        print('check_esp_section_attr: no %s binutils, %s NOT verified' % (arch, chip))
        return
    obj = os.path.join(tmp, 'c_secattr_%s.o' % chip)
    subprocess.run([cc, '--target=' + chip, '--freestanding', '--emit-obj', SRC, obj],
                   check=True, stdout=subprocess.DEVNULL)
    secs = sections(b, obj)
    idx = {}
    for name, rows in secs.items():
        for r in rows:
            idx[r[0]] = name

    def want(what, got, exp):
        if got != exp:
            fails.append('%s %s: got %r, want %r' % (chip, what, got, exp))

    want('.rodata_desc count', len(secs.get('.rodata_desc', [])), 2)
    for name, flg in (('.rodata_desc', 'A'), ('.dram1.flags', 'WA'), ('.noinit.keep', 'WA')):
        for r in secs.get(name, []):
            want(name + ' flags', r[3], flg)
    syms = {}
    for line in run(b + 'readelf', '-sW', obj).splitlines():
        p = line.split()
        if len(p) == 8 and p[6].isdigit():
            syms[p[7]] = (int(p[1], 16), int(p[2]), idx.get(int(p[6])))
    want('esp_app_desc section', syms.get('esp_app_desc', (0, 0, None))[2], '.rodata_desc')
    want('flags section', syms.get('flags', (0, 0, None))[2], '.dram1.flags')
    want('keep section', syms.get('keep', (0, 0, None))[2], '.noinit.keep')
    want('counter section', syms.get('counter', (0, 0, None))[2], '.data')
    want('cache_init section', syms.get('cache_init', (0, 0, None))[2], '.iram1.text')
    want('xtensa_start section', syms.get('xtensa_start', (0, 0, None))[2], '.iram1.text')
    # every function starts word-aligned: CALLn targets must be, and the
    # inline L32R pools were laid out for an aligned start (Gibux's
    # caches_init sat at .iram1.text+0x77 and read its frame size off-word)
    for name, (val, _sz, sec) in syms.items():
        if sec in ('.text', '.iram1.text') and name in (
                'cache_init', 'xtensa_start', 'flash_mid', 'later'):
            if val % 4:
                fails.append('%s %s at %s+%#x, not word-aligned' % (chip, name, sec, val))
    want('flash_mid section', syms.get('flash_mid', (0, 0, None))[2], '.text')
    want('later section', syms.get('later', (0, 0, None))[2], '.text')
    dump = run(b + 'objdump', '-s', '-j', '.rodata_desc', '-j', '.dram1.flags', obj)
    blobs, cur = {}, None
    for line in dump.splitlines():
        m = re.match(r'Contents of section (\S+):', line)
        if m:
            cur = m.group(1)
            blobs.setdefault(cur, []).append(b'')
            continue
        p = line.split()
        if cur and len(p) >= 2 and re.fullmatch(r'[0-9a-f]{4,}', p[0]):
            for w in p[1:5]:
                if re.fullmatch(r'[0-9a-f]{2,8}', w):
                    blobs[cur][-1] += bytes.fromhex(w)
    descs = sorted(blobs.get('.rodata_desc', []), key=len)
    if len(descs) == 2:
        want('desc_tail bytes', descs[0], struct.pack('<I', 0x11223344))
        d = descs[1]
        want('esp_app_desc size', len(d), 256)
        want('esp_app_desc magic', d[0:8], struct.pack('<II', 0xABCD5432, 3))
        want('esp_app_desc version', d[16:16 + 10], b'gibux-0.1\0')
        want('esp_app_desc project', d[48:48 + 6], b'gibux\0')
    want('flags bytes', blobs.get('.dram1.flags', [b''])[0], struct.pack('<i', 0x55))
    dis = run(b + 'objdump', '-dr', '-j', '.iram1.text', obj)
    iram_size = secs['.iram1.text'][0][2]
    # pxx emits no $d mapping symbols, so objdump decodes the inline literal
    # pools as instructions; judge by relocations and bytes instead. An l32r
    # reaching a pool outside .iram1.text would need a SLOT0 relocation, and
    # an iram->iram call goes through an R_*_32 literal against the callee.
    rels = re.findall(r'R_(?:XTENSA|RISCV)_\w+', dis)
    if arch == 'xtensa':
        bad = [r for r in rels if r != 'R_XTENSA_32']
        if bad:
            fails.append('%s: .iram1.text carries %s (a literal outside it?)' % (chip, bad))
    if not re.search(r'R_(XTENSA|RISCV)_32\s+cache_init', dis):
        fails.append(chip + ': the iram->iram call is not relocated')
    if arch != 'xtensa':
        return
    lds = os.path.join(tmp, 'c_secattr.ld')
    elf = os.path.join(tmp, 'c_secattr.elf')
    with open(lds, 'w') as f:
        f.write('SECTIONS { . = 0x3c000020; .flash.appdesc : { KEEP(*(.rodata_desc)) } '
                '.flash.rodata : { *(.rodata*) } '
                '. = 0x40370000; .iram0.text : { *(.iram1*) } '
                '. = 0x42000020; .flash.text : { *(.text*) } '
                '. = 0x3fc88000; .dram0.data : { *(.data*) *(.dram1*) } '
                '.noinit (NOLOAD) : { *(.noinit*) } .bss : { *(.bss*) } }\n'
                'ENTRY(xtensa_start)\n')
    subprocess.run([b + 'ld', '-T', lds, obj, '-o', elf], check=True)
    nm = {}
    for line in run(b + 'nm', elf).splitlines():
        p = line.split()
        if len(p) == 3:
            nm[p[2]] = int(p[0], 16)
    want('linked esp_app_desc', nm.get('esp_app_desc'), 0x3c000020)
    for f in ('cache_init', 'xtensa_start'):
        if not 0x40370000 <= nm.get(f, 0) < 0x40380000:
            fails.append('linked %s at %#x, not in IRAM' % (f, nm.get(f, 0)))
    for f in ('flash_mid', 'later'):
        if not 0x42000000 <= nm.get(f, 0) < 0x43000000:
            fails.append('linked %s at %#x, not in flash' % (f, nm.get(f, 0)))
    raw = b''
    for line in run(b + 'objdump', '-s', '-j', '.iram0.text', elf).splitlines():
        p = line.split()
        if len(p) >= 2 and re.fullmatch(r'[0-9a-f]{8}', p[0]):
            for w in p[1:5]:
                if re.fullmatch(r'[0-9a-f]{2,8}', w):
                    raw += bytes.fromhex(w)
    for f in ('cache_init', 'counter', 'flags', 'keep'):
        if struct.pack('<I', nm[f]) not in raw:
            fails.append('linked IRAM code holds no literal with %s\'s address' % f)


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    fails = []
    check(cc, tmp, 'xtensa', 'esp32s3', fails)
    check(cc, tmp, 'riscv', 'esp32c3', fails)
    if fails:
        print('check_esp_section_attr: FAIL')
        for x in fails:
            print('  ' + x)
        return 1
    print('check_esp_section_attr: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
