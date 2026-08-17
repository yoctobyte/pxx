#!/usr/bin/env python3
"""Count the raw kernel-entry instructions in a pxx-emitted binary.

This is the acceptance instrument for feature-port-rtl-over-libc: "the emitted
binary contains zero `syscall` instructions (all kernel access via libc PLT)".

It exists because the obvious spelling of that check is silently useless. pxx
writes ELFs with **program headers only and no section headers**, and
`objdump -d` disassembles *sections* — so

    objdump -d <pxx binary> | grep -c syscall

prints 0 for every pxx binary ever built, including one that makes 57 raw
syscalls. It does not fail, warn, or produce empty output that looks wrong; it
prints a three-line header and a zero. An acceptance test written that way
passes on day one and keeps passing no matter what the compiler does.

So: read the program headers directly, disassemble each executable PT_LOAD as
raw bytes at its true vaddr, and count the kernel-entry mnemonic for the ELF's
own e_machine. Refuses to report a count it could not actually measure.

Usage:
    tools/syscall_scan.py <binary>              # print the count
    tools/syscall_scan.py <binary> --list       # ...and every site's address
    tools/syscall_scan.py <binary> --expect-zero  # exit 1 if any remain
"""

import struct
import tempfile
import subprocess
import sys

# e_machine -> (objdump -m argument, kernel-entry mnemonics for that ISA)
#
# Listed per architecture because the instruction is not called "syscall"
# anywhere but x86-64, and a scan that greps for that word alone reports a
# clean zero on every cross target — the same silent-pass this tool exists to
# stop, one level down.
ARCHES = {
    0x03: ("i386", ("int    $0x80", "sysenter")),
    0x3E: ("i386:x86-64", ("syscall",)),
    0x28: ("arm", ("svc",)),
    0xB7: ("aarch64", ("svc",)),
    0xF3: ("riscv:rv32", ("ecall",)),
    0x5E: ("xtensa", ("syscall",)),
}

PT_LOAD = 1
PF_X = 1


def exec_segments(blob):
    """Every executable PT_LOAD as (file_offset, vaddr, filesz)."""
    if blob[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file")
    if blob[4] != 2:
        raise SystemExit("only 64-bit ELF is handled; 32-bit targets need the "
                         "32-bit program-header layout adding here")
    e_machine = struct.unpack_from("<H", blob, 0x12)[0]
    phoff = struct.unpack_from("<Q", blob, 0x20)[0]
    phentsize = struct.unpack_from("<H", blob, 0x36)[0]
    phnum = struct.unpack_from("<H", blob, 0x38)[0]

    out = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, p_flags = struct.unpack_from("<II", blob, off)
        p_offset, p_vaddr = struct.unpack_from("<QQ", blob, off + 8)
        p_filesz = struct.unpack_from("<Q", blob, off + 32)[0]
        if p_type == PT_LOAD and (p_flags & PF_X) and p_filesz:
            out.append((p_offset, p_vaddr, p_filesz))
    return e_machine, out


def disassemble(chunk, march, vaddr):
    # A real file, not a pipe: objdump seeks, so /dev/stdin gives
    # "not an ordinary file" and an empty disassembly — which would read as a
    # count of zero, the exact failure this tool exists to prevent.
    with tempfile.NamedTemporaryFile(suffix=".bin") as tmp:
        tmp.write(chunk)
        tmp.flush()
        proc = subprocess.run(
            ["objdump", "-D", "-b", "binary", "-m", march,
             "--adjust-vma=0x%x" % vaddr, tmp.name], capture_output=True)
    if proc.returncode != 0:
        raise SystemExit("objdump failed for -m %s:\n%s"
                         % (march, proc.stderr.decode("utf-8", "replace")))
    out = proc.stdout.decode("utf-8", "replace")
    if "\tint3" not in out and len(out.splitlines()) < 4:
        raise SystemExit("objdump produced no disassembly for -m %s: nothing "
                         "was measured, which is not a count of zero" % march)
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a for a in argv[1:] if a.startswith("--")}
    if len(args) != 1:
        raise SystemExit(__doc__)

    blob = open(args[0], "rb").read()
    e_machine, segments = exec_segments(blob)
    if e_machine not in ARCHES:
        raise SystemExit("unhandled e_machine 0x%x — add it to ARCHES rather "
                         "than letting the scan report a clean zero" % e_machine)
    march, mnemonics = ARCHES[e_machine]

    if not segments:
        raise SystemExit("no executable PT_LOAD segment: nothing was measured, "
                         "which is not the same as a count of zero")

    sites = []
    for p_offset, p_vaddr, p_filesz in segments:
        text = disassemble(blob[p_offset:p_offset + p_filesz], march, p_vaddr)
        for line in text.splitlines():
            # objdump lines look like "  400123:\t0f 05\tsyscall". Match on the
            # mnemonic field only, so a data byte that happens to render as an
            # address or an operand cannot be counted as an instruction.
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            insn = parts[2].strip()
            if any(insn == m or insn.startswith(m + " ") for m in mnemonics):
                sites.append((parts[0].strip().rstrip(":"), insn))

    if "--list" in flags:
        for addr, insn in sites:
            print("  %s  %s" % (addr, insn))

    print("%s: %d kernel-entry instruction(s) [%s]"
          % (args[0], len(sites), march))

    if "--expect-zero" in flags and sites:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
