#!/usr/bin/env python3
"""Count the x86-64 --threadsafe heap lock's ASYNC-RE-ENTRY REFUSAL in a binary.

bug-a-compiler-emitted-runtime-stubs-are-invisible-to-every-gate-we-run: the
heap-lock stubs are codegen that compiler.pas never causes to be emitted, so
neither the self-host fixedpoint nor a gate tier can see them change. 12d6c86f0
fixed a regression that shipped for three days: a signal handler was granted the
lock on a bare tid match because the alt-stack bounds test had silently stopped
being emitted. The runtime test for it only catches the bug by winning a race.
This reads the emitted bytes instead, which is deterministic.

THE SHAPE (EmitHeapLockStubs, ir_codegen.inc), matched exactly:

    mov  %rsp,%rcx
    lea  LO(%rip),%rax     ; BSS_SIG_ALTSTK
    cmp  %rax,%rcx
    jb   ...
    lea  HI(%rip),%rax     ; BSS_SIG_ALTSS, which must be LO + SIG_ALTSTACK_SIZE
    cmp  %rax,%rcx
    jae  ...
    jmp  ...               ; inside the alt stack: refuse the grant

THE DECOY the ticket warns about: the TLS tid-safety check right beside it ALSO
does `mov %rsp,%rcx` and two bounds compares (against 0x10(%rsi)/0x18(%rsi)).
Asserting "a bounds compare after mov rsp,rcx" passes on the broken build. So
this matches the rip-relative pair and checks the distance between them.

The binary is sectionless, so it is disassembled as a raw image.

usage: check_heaplock_async_refusal.py BINARY ALTSTACK_SIZE  -> prints the count
"""
import re
import subprocess
import sys


def main():
    path, size = sys.argv[1], int(sys.argv[2])
    out = subprocess.run(
        ['objdump', '-D', '-b', 'binary', '-m', 'i386:x86-64', '--no-show-raw-insn', path],
        capture_output=True, text=True, check=True).stdout
    ins = []
    for line in out.splitlines():
        m = re.match(r'\s*[0-9a-f]+:\s+(.*)$', line)
        if m:
            ins.append(m.group(1).strip())
    lea = re.compile(r'lea\s+\S+\(%rip\),%rax\s+#\s+0x([0-9a-f]+)')
    n = 0
    for i in range(len(ins) - 7):
        if not re.match(r'mov\s+%rsp,%rcx$', ins[i]):
            continue
        lo, hi = lea.match(ins[i + 1]), lea.match(ins[i + 4])
        if not (lo and hi):
            continue
        if not (re.match(r'cmp\s+%rax,%rcx$', ins[i + 2]) and ins[i + 3].startswith('jb ')
                and re.match(r'cmp\s+%rax,%rcx$', ins[i + 5]) and ins[i + 6].startswith('jae ')
                and ins[i + 7].startswith('jmp ')):
            continue
        if int(hi.group(1), 16) - int(lo.group(1), 16) != size:
            continue
        n += 1
    print(n)


main()
