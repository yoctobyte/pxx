#!/usr/bin/env python3
"""A pxx xtensa object links as a PIE (ld -pie), the format Nilix loads.

Builds test/c_xtensa_pie_hello.c windowed with --emit-obj --no-ro-data, links
it with test/xtensa_pie_prog.ld, and requires: ET_DYN, no PT_INTERP, only
R_XTENSA_RELATIVE dynamic relocations, and an R+X PT_LOAD that holds .text
alone. Before the object carried .xt.lit, ld refused every literal with
"dynamic relocation in read-only section". Also: the linked .text equals the
object's except at the relocated words (ld relaxed nothing), and every
pointer in data is word-aligned. And a C program with main()
(test/c_xtensa_pie_main.c, crtl included) links with `-e app_main` to the
same shape (feature-xtensa-gibux-user-programs-as-et-dyn-pie). Exits 0, saying
so, without the xtensa binutils (~/.espressif).
usage: tools/check_xtensa_pie_link.py <compiler> <tmpdir>
feature-xtensa-objects-carry-a-literal-table
"""
import glob
import os
import re
import subprocess
import sys


def unaligned_data_relocs(readelf, obj):
    """R_XTENSA_32 in any data section (not code, not .xt.lit) at an offset
    that is not a multiple of 4: a pointer the S3 faults loading, and one
    Nilix's loader refuses to relocate."""
    out = subprocess.run([readelf, '-rW', obj], capture_output=True, text=True).stdout
    sec, bad = None, []
    for line in out.splitlines():
        m = re.match(r"Relocation section '([^']+)'", line)
        if m:
            sec = m.group(1)
            continue
        m = re.match(r'([0-9a-f]{8})\s+\S+\s+R_XTENSA_32\b', line)
        if m and sec and 'text' not in sec and 'xt.lit' not in sec and int(m.group(1), 16) % 4:
            bad.append('%s+0x%x' % (sec, int(m.group(1), 16)))
    return bad


def pie_shape(b, elf):
    """None when elf is ET_DYN, has no PT_INTERP and only RELATIVE relocations;
    else what is wrong"""
    hl = subprocess.run([b + 'readelf', '-hlW', elf], capture_output=True, text=True).stdout
    if 'DYN (' not in hl:
        return 'not ET_DYN'
    if 'INTERP' in hl:
        return 'has PT_INTERP'
    rel = subprocess.run([b + 'readelf', '-rW', elf], capture_output=True, text=True).stdout
    types = set(re.findall(r'\b(R_XTENSA_\w+)', rel))
    if types != {'R_XTENSA_RELATIVE'}:
        return 'relocation types %s' % sorted(types)
    return None


def main_program(cc, b, tmp):
    obj = os.path.join(tmp, 'c_xt_pie_main.o')
    elf = os.path.join(tmp, 'c_xt_pie_main.elf')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
                    '--xtensa-abi=windowed', '--no-ro-data', '--emit-obj',
                    'test/c_xtensa_pie_main.c', obj], check=True, stdout=subprocess.DEVNULL)
    r = subprocess.run([b + 'ld', '-pie', '--no-dynamic-linker', '-e', 'app_main',
                        '-T', 'test/xtensa_pie_prog.ld', obj, '-o', elf],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return 'ld: ' + (r.stderr.strip().splitlines() or ['?'])[0]
    return pie_shape(b, elf)


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-ld')))
    obj = os.path.join(tmp, 'c_xt_pie.o')
    subprocess.run([cc, '--target=xtensa', '--platform=posix', '--xtensa-soft-mulhigh',
                    '--xtensa-abi=windowed', '--no-ro-data', '--emit-obj',
                    'test/c_xtensa_pie_hello.c', obj], check=True, stdout=subprocess.DEVNULL)
    if not bins:
        print('check_xtensa_pie_link: no xtensa binutils, NOT run')
        return 0
    b = bins[-1][:-len('ld')]
    # every pointer in data is word-aligned: the PIE object, and a Pascal ESP
    # object with classes and the read-only split (TObject's VMT sat at Data
    # offset 42 on every target; bug-a-vmt-placed-at-an-unaligned-data-offset)
    pobj = os.path.join(tmp, 'c_xt_pie_cls.o')
    subprocess.run([cc, '--target=esp32s3', '--emit-obj', 'test/esp_obj_class_slots_need_a_class.pas',
                    pobj], check=True, stdout=subprocess.DEVNULL)
    for o in (obj, pobj):
        bad = unaligned_data_relocs(b + 'readelf', o)
        if bad:
            print('check_xtensa_pie_link: FAIL, unaligned pointers in data: ' + ', '.join(bad[:4]))
            return 1
    elf = os.path.join(tmp, 'c_xt_pie.elf')
    r = subprocess.run([b + 'ld', '-pie', '--no-dynamic-linker', '-T', 'test/xtensa_pie_prog.ld',
                        obj, '-o', elf], capture_output=True, text=True)
    if r.returncode != 0:
        print('check_xtensa_pie_link: FAIL, ld: ' + (r.stderr.strip().splitlines() or ['?'])[0])
        return 1
    hl = subprocess.run([b + 'readelf', '-hlW', elf], capture_output=True, text=True).stdout
    if 'DYN (' not in hl:
        print('check_xtensa_pie_link: FAIL, not ET_DYN')
        return 1
    if 'INTERP' in hl:
        print('check_xtensa_pie_link: FAIL, has PT_INTERP')
        return 1
    rel = subprocess.run([b + 'readelf', '-rW', elf], capture_output=True, text=True).stdout
    types = set(re.findall(r'\b(R_XTENSA_\w+)', rel))
    if types != {'R_XTENSA_RELATIVE'}:
        print('check_xtensa_pie_link: FAIL, relocation types %s' % sorted(types))
        return 1
    loads = re.findall(r'^\s*LOAD\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+(R E|RW )', hl, re.M)
    sec = subprocess.run([b + 'readelf', '-SW', elf], capture_output=True, text=True).stdout
    m = re.search(r'\]\s+\.text\s+PROGBITS\s+(\S+)\s+\S+\s+(\S+)', sec)
    rx = [(int(v, 16), int(s, 16)) for v, s, fl in loads if fl == 'R E']
    if len(rx) != 1 or not m or int(m.group(1), 16) + int(m.group(2), 16) != rx[0][0] + rx[0][1]:
        print('check_xtensa_pie_link: FAIL, the R+X segment is not .text alone: %s' % loads)
        return 1
    to, te = os.path.join(tmp, 'c_xt_pie_o.bin'), os.path.join(tmp, 'c_xt_pie_e.bin')
    subprocess.run([b + 'objcopy', '-O', 'binary', '-j', '.text', obj, to], check=True)
    subprocess.run([b + 'objcopy', '-O', 'binary', '-j', '.text', elf, te], check=True)
    a, e = open(to, 'rb').read(), open(te, 'rb').read()
    nrel = len(re.findall(r'R_XTENSA_32', subprocess.run([b + 'readelf', '-rW', obj],
               capture_output=True, text=True).stdout.split("'.rela.data'")[0]))
    diff = sum(1 for i in range(0, len(a), 4) if a[i:i + 4] != e[i:i + 4])
    if len(a) != len(e) or diff > nrel:
        print('check_xtensa_pie_link: FAIL, ld changed .text (%d vs %d bytes, %d words)' % (len(a), len(e), diff))
        return 1
    why = main_program(cc, b, tmp)
    if why:
        print('check_xtensa_pie_link: FAIL, the main() program: ' + why)
        return 1
    print('check_xtensa_pie_link: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
