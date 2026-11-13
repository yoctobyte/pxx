---
track: C
tags: [c, x86-64, inline-asm, gibux, dropbear, asmenc]
prio: 40
type: bug
blocked-by: []
summary: "AT&T inline asm refused instructions that Gibux SMP and dropbear's sntrup761.c use. Added: the lock prefix (`lock op` and `lock;`), cmpxchg, xadd, str, sldt, sgdt, sidt, rdtscp, rdpid, bsf, bsr and cmov<cc>. Encodings are checked against gas; semantics are checked against gcc at run time."
status: done
owner: claude
---

# lock, cmpxchg, xadd, bsf/bsr, cmov<cc> and the descriptor reads in inline asm

Two sources:

- **Gibux** (a kernel built with pxx) asked for these through the owner's
  relay. `lock cmpxchgl` and `lock xaddl` back its futex and spinlocks. A
  `lock` that is lost is a real lost-wakeup hang on SMP, so this was their top
  priority. `str` reads the TSS selector to find the current CPU. `rdtscp`,
  `rdpid`, `sldt`, `sgdt` and `sidt` were on the same list.
- **dropbear 2026.94** ([[feature-c-dropbear-builds-with-pxx]]):
  sntrup761.c's constant-time helpers use `bsfw`/`bsfl` and the whole cmov
  family with a size suffix (`cmovnew`, `cmovlq`, ...).

**What changed.**

- `compiler/asmatt.inc`: the AT&T reader knows these bases. `lock` is read as
  a prefix and emits F0 before the instruction, so F0 comes ahead of the
  66/REX bytes the instruction emits itself. Both spellings work: `lock op`
  on one line, and `lock;` or a bare `lock` followed by a separator. The i386
  text path refuses `lock` by name.
- `compiler/asmenc.inc`:
  - cmpxchg is 0F B0/B1; xadd is 0F C0/C1.
  - bsf/bsr are 0F BC/BD, with no 8-bit form.
  - rdtscp is 0F 01 F9.
  - rdpid is F3 [REX.B] 0F C7 /7. F3 is a mandatory prefix, so it comes
    before REX.
  - str/sldt are 0F 00 /1 and /0. A 16-bit register takes 66. A 32- or 64-bit
    register takes no width prefix, as gas does it (`str %rax` assembles as
    `str %eax`). The memory form has no prefix.
  - sgdt/sidt are 0F 01 /0 and /1, memory only.

**Tests.**

- `test/casm_att_atomics_sysregs.att`, through `tools/casm_att_diff.py
  --self-check`. 27 instructions, each disassembling exactly as gas assembles
  the same text. The list includes r8-r15 on both sides, because prefix order
  is what goes wrong. The first run caught `str %rax`: pxx added a REX.W that
  gas leaves out.
- `test/casm_lock_cmpxchg_xadd_bsf.c` (row `casmlock26`, against gcc -O0):
  - Gibux's cmpxchg shape, on both the hit and the miss arm.
  - `lock;`, xadd's returned old value, and lock inc/dec/or/and.
  - bsf/bsr in w/l/q, and sntrup761's bsfw + cmovew bottom-bit idiom.

  The privileged and CPU-dependent instructions are not executed (UMIP, and
  rdpid is missing on older CPUs). The gas oracle covers their bytes.
- `test/c_big_struct_by_value_and_cmov.c` carries sntrup761's cmov helpers
  verbatim.
