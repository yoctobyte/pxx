---
track: C
tags: [C, inline-asm, i386]
prio: 50
type: bug
blocked-by: []
summary: "On --target=i386, `__asm volatile(\"bswap %0\" : \"+r\"(x))` with a 32-bit unsigned long is refused (\"inline asm template has an unsupported instruction: bswap\"); gcc -m32 accepts it and x86-64 pxx encodes it."
status: done
owner: pxx (Rainyday seat)
created: 2026-11-19
found-by: pxx (Rainyday seat), while testing bug-c-asm-in-an-unused-static-inline-function-stops-the-compile
---

# i386: inline asm `bswap` with an "+r" operand is refused

    unsigned long ok(unsigned long x) { __asm volatile("bswap %0" : "+r"(x)); return x; }
    int main(void) { return ok(0x01000000UL) == 1 ? 0 : 1; }

- `pascal26 --target=i386`: error `C: inline asm template has an unsupported instruction: bswap` (latest and master, 2026-11-19).
- `gcc -m32`: compiles, exits 0. pxx on x86-64 encodes it.

The i386 path renders Intel text lines for asmtext_386 (AttSinkText); bswap is probably missing from that table, or the suffix-less mnemonic with a register operand is not split. Note: since 3dd7b0ed00, inside a `static` routine this poisons the routine instead of stopping the compile.

## Done 2026-11-19

The i386 text sink did not know the mnemonic: asmatt.inc's AttKnows386 now
lists `bswap`, and asmtext_386.inc assembles `bswap r32` as 0F C8+r (a
32-bit register only, as gas). Test: a `swap32` row in
test/casm_gnu_operands_i386.c, which the Makefile already compares against
gcc -m32 (`bswap 04030201 d0c0b0a0`). Latest refuses the file.
