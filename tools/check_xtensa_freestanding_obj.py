#!/usr/bin/env python3
"""A freestanding xtensa object is data, not a program: link it and read it.

Compiles test/c_freestanding_static_data.c with
  --target=esp32s3 --freestanding --emit-obj -DPXX_NO_MAIN
and checks, with Espressif's binutils:
  - the object has no undefined symbol (no ESP-IDF runtime underneath) and
    its app_main is WEAK;
  - it is windowed code (the chip's ABI, what gcc emits);
  - linked by GNU ld at fixed addresses, every initialised global holds the
    value or the address gcc would have put there.
Exits 0, saying so, when the toolchain is absent.
usage: tools/check_xtensa_freestanding_obj.py <compiler> <tmpdir>
feature-xtensa-freestanding-objects-carry-the-idf-application-runtime
"""
import glob
import os
import struct
import subprocess
import sys


def main():
    cc, tmp = sys.argv[1], sys.argv[2]
    bins = sorted(glob.glob(os.path.expanduser(
        '~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin')))
    if not bins:
        print('check_xtensa_freestanding_obj: no xtensa-esp32s3-elf binutils, NOT verified')
        return 0
    b = bins[-1] + '/xtensa-esp32s3-elf-'
    obj = os.path.join(tmp, 'c_fsd_xt.o')
    elf = os.path.join(tmp, 'c_fsd_xt.elf')
    lds = os.path.join(tmp, 'c_fsd_xt.ld')
    subprocess.run([cc, '--target=esp32s3', '--freestanding', '--emit-obj', '-DPXX_NO_MAIN',
                    'test/c_freestanding_static_data.c', obj],
                   check=True, stdout=subprocess.DEVNULL)
    fails = []
    nm = subprocess.run([b + 'nm', obj], check=True, capture_output=True, text=True).stdout
    for line in nm.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == 'U':
            fails.append('undefined symbol in a freestanding object: ' + parts[1])
        if len(parts) == 3 and parts[2] == 'app_main' and parts[1] != 'W':
            fails.append('app_main is ' + parts[1] + ', not weak')
    dis = subprocess.run([b + 'objdump', '-d', obj], check=True, capture_output=True,
                         text=True).stdout
    if '\tentry\t' not in dis or 'retw' not in dis:
        fails.append('not windowed code (no entry/retw)')
    with open(lds, 'w') as f:
        f.write('SECTIONS { . = 0x40000000; .text : { *(.text*) } '
                '. = 0x3fc90000; .rodata : { *(.rodata*) } .data : { *(.data*) } '
                '.bss : { *(.bss*) *(COMMON) } }\nENTRY(check)\n')
    subprocess.run([b + 'ld', '-T', lds, obj, '-o', elf], check=True)
    syms = {}
    for line in subprocess.run([b + 'nm', elf], check=True, capture_output=True,
                               text=True).stdout.splitlines():
        parts = line.split()
        if len(parts) == 3:
            syms[parts[2]] = int(parts[0], 16)
    mem = {}
    for line in subprocess.run([b + 'objdump', '-s', '-j', '.rodata', '-j', '.data', elf],
                               check=True, capture_output=True, text=True).stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            addr = int(parts[0], 16)
        except ValueError:
            continue
        for k, word in enumerate(parts[1:5]):
            try:
                data = bytes.fromhex(word)
            except ValueError:
                break
            for j, by in enumerate(data):
                mem[addr + 4 * k + j] = by

    def word(a):
        return struct.unpack('<I', bytes(mem.get(a + i, 0) for i in range(4)))[0]

    def cstr(a):
        out = b''
        while mem.get(a, 0):
            out += bytes([mem[a]])
            a += 1
        return out

    def want(what, got, exp):
        if got != exp:
            fails.append('%s: got %r, want %r' % (what, got, exp))

    s = syms
    want('counter', word(s['counter']), 7)
    want('tbl', bytes(mem.get(s['tbl'] + i, 0) for i in range(8)),
         struct.pack('<4h', 1, -2, 3, -4))
    want('*greet', cstr(word(s['greet'])), b'hello')
    want('pc', word(s['pc']), s['counter'])
    want('pt', word(s['pt']), s['tbl'] + 4)
    want('big', bytes(mem.get(s['big'] + i, 0) for i in range(8)),
         struct.pack('<Q', 0x1122334455667788))
    want('*devb.name', cstr(word(s['devb'])), b'devb')
    want('devb.irq', word(s['devb'] + 4), 9)
    want('*deva.name', cstr(word(s['deva'])), b'deva')
    want('deva.irq', word(s['deva'] + 4), 5)
    want('deva.probe', word(s['deva'] + 8), s['probe_a'])
    want('deva.next', word(s['deva'] + 12), s['devb'])
    want('pz', word(s['pz']), s['zero_one'])
    want('uart', word(s['uart']), 0x60000000)
    want('self', word(s['self']), s['self'])
    want('bp', word(s['bp']), s['buf'] + 2)
    want('ip', word(s['ip']), s['ia'] + 12)
    want('lh0', (word(s['lh0']), word(s['lh0'] + 4)), (0, 4))
    if fails:
        print('check_xtensa_freestanding_obj: FAIL')
        for x in fails:
            print('  ' + x)
        return 1
    print('check_xtensa_freestanding_obj: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
