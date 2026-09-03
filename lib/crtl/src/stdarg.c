/* SPDX-License-Identifier: Zlib */
/* va_list helpers — the bodies that used to sit in <stdarg.h>.

   Moved here 2026-08-19 (bug-c-header-with-a-body-compiles-twice-across-the-
   macro-reset). They are auto-pulled as this header's sibling, once per compile
   (CrtlSrcPulled in defs.inc), so including stdarg.h twice is now free.

   External linkage is required, not stylistic: cparser.inc resolves each of
   these by name via FindProc when lowering __builtin_va_start / __builtin_va_arg. */
#include <stdarg.h>

/* va_start, in plain C: seed the control block with the BYTE offsets at which
   the first variadic argument of each class sits inside the register save area,
   already past the named params that consumed slots ahead of it.

   THE OFFSETS ARRIVE AS BYTES, computed by the frontend, because the save-area
   LAYOUT is per-target and a seeder that converts slot counts can only know one
   of them: SysV x86-64 is a 48-byte GP region then 8 XMM slots of 16, aarch64 is
   a 64-byte GP region then 8 d slots of 8. This used to take ngp/nfp and hard-
   code the SysV arithmetic, which is why aarch64 could not have an FP region at
   all. overflow points at the first caller stack slot past the register banks.
   bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero */
void __pxx_va_start_impl(struct __pxx_va_elem *ap, void *save,
                                unsigned int gpoff, void *overflow,
                                unsigned int fpoff) {
  ap->gp_offset = gpoff;
  ap->fp_offset = fpoff;
  ap->reg_save_area = save;
  ap->overflow_arg_area = overflow;
}

/* va_arg gp/fp/overflow walk, in plain C. Returns the address of the next
   integer/pointer (gp) or floating (fp) variadic argument and advances. */
void *__pxx_va_arg_gp(struct __pxx_va_elem *ap) {
  void *addr;
  if (ap->gp_offset < 48) {
    addr = (char *)ap->reg_save_area + ap->gp_offset;
    ap->gp_offset = ap->gp_offset + 8;
  } else {
    addr = ap->overflow_arg_area;
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + 8;
  }
  return addr;
}

/* SysV AMD64: floating variadic args arrive in XMM0..7, saved to the FP region
   of the save area (offset 48, one 16-byte slot each). Read from fp_offset and
   advance by 16; past the 8 XMM slots (offset 176) spill to the overflow area. */
void *__pxx_va_arg_fp(struct __pxx_va_elem *ap) {
  void *addr;
  if (ap->fp_offset < 176) {
    addr = (char *)ap->reg_save_area + ap->fp_offset;
    ap->fp_offset = ap->fp_offset + 16;
  } else {
    addr = ap->overflow_arg_area;
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + 8;
  }
  return addr;
}

/* va_arg of a STRUCT or UNION on SysV AMD64, which is the one shape the two
   helpers above cannot serve: an aggregate occupies one eightbyte SLOT PER
   EIGHTBYTE, and the classifier decides per eightbyte whether that slot is an
   INTEGER (gp) or SSE (fp) one -- so a `struct { double a, b; }` lands in two
   XMM slots that are SIXTEEN bytes apart in the save area, not contiguous.
   Nothing that returns a single address can describe it, which is why this one
   copies into a caller-supplied destination instead.

   `ssemask` bit k = eightbyte k is SSE-classified; `neight` = how many there
   are; `size` = the aggregate's byte size. The frontend computes all three from
   the SAME ABISysVArgPlace oracle the CALLER used to place the argument, which
   is what makes the two halves agree.

   THE ALL-OR-NOTHING RULE IS THE PART A PER-SLOT HELPER GETS WRONG: SysV says
   an aggregate whose eightbytes cannot ALL be placed in registers goes to
   memory ENTIRELY. Walking it a slot at a time would take eightbyte 0 from a
   register and eightbyte 1 from the overflow area, which is a plausible wrong
   answer rather than a crash -- it needs five earlier GP variadic arguments to
   show up. The check is done once, here, before any offset moves.
   bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer */
void __pxx_va_arg_agg(struct __pxx_va_elem *ap, void *dst,
                      unsigned int neight, unsigned int ssemask,
                      unsigned int size) {
  unsigned int k, ngp, nsse, i;
  char *d;
  char *src;
  d = (char *)dst;
  ngp = 0;
  nsse = 0;
  for (k = 0; k < neight; k = k + 1) {
    if ((ssemask >> k) & 1u) nsse = nsse + 1;
    else ngp = ngp + 1;
  }
  /* neight == 0 IS the MEMORY class, straight from ABISysVRecordEightbytes,
     which returns 0 for both of its memory answers (size > 16, and a <=16-byte
     record the walk classified MEMORY). Inferring it from `size > 16` here
     would get the second one wrong, and getting it wrong is a plausible value
     rather than a fault. The bank-full test is the SAME all-or-nothing rule
     ABISysVArgPlace applies on the caller's side; both sides must reach the
     same answer or every argument after this one is off by a slot. */
  if (neight == 0 || ap->gp_offset + ngp * 8 > 48 ||
      ap->fp_offset + nsse * 16 > 176) {
    /* MEMORY: the bytes are contiguous in the caller's stack area, 8-aligned. */
    src = (char *)ap->overflow_arg_area;
    for (i = 0; i < size; i = i + 1) d[i] = src[i];
    ap->overflow_arg_area = (void *)(src + ((size + 7u) & ~7u));
    return;
  }
  for (k = 0; k < neight; k = k + 1) {
    if ((ssemask >> k) & 1u) {
      src = (char *)ap->reg_save_area + ap->fp_offset;
      ap->fp_offset = ap->fp_offset + 16;
    } else {
      src = (char *)ap->reg_save_area + ap->gp_offset;
      ap->gp_offset = ap->gp_offset + 8;
    }
    for (i = 0; i < 8; i = i + 1) {
      if (k * 8 + i < size) d[k * 8 + i] = src[i];
    }
  }
}

/* aarch64 variadic model: TWO banks, as AAPCS64 §6.4.2 describes and as the
   target's own glibc demonstrates — x0..x7 for integers and pointers, v0..v7 for
   floating point. The save area is 8 GP slots of 8 bytes at offset 0 and 8 FP
   slots of 8 bytes at offset 64 (a d register is the whole of a pxx float value,
   so the 16-byte q slots of the real AAPCS64 layout would be padding).

   This one walks the GP bank. It reads EVERY type on the pointer/integer side,
   including a struct-by-value tail argument, which this target passes as a
   pointer to the caller's copy.

   It used to be the only walk, on the belief that pxx's GP-bits value model
   extended to the calling convention. It does, between two pxx frames, which is
   exactly why no pxx-vs-pxx test could see it: `printf("%.2f")` through crtl was
   green while the same call into glibc printed 0.00.
   bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero */
void *__pxx_va_arg_cross(struct __pxx_va_elem *ap) {
  void *addr;
  if (ap->gp_offset < 64) {
    addr = (char *)ap->reg_save_area + ap->gp_offset;
    ap->gp_offset = ap->gp_offset + 8;
  } else {
    addr = ap->overflow_arg_area;
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + 8;
  }
  return addr;
}

/* aarch64 FP bank: 8 slots of 8 bytes at save-area offset 64, so the region ends
   at 128. Past it the argument was placed on the caller's stack, in the ONE
   shared NSAA both banks overflow into — which is why this advances the same
   overflow_arg_area by the same 8 bytes the GP walk does. */
void *__pxx_va_arg_a64_fp(struct __pxx_va_elem *ap) {
  void *addr;
  if (ap->fp_offset < 128) {
    addr = (char *)ap->reg_save_area + ap->fp_offset;
    ap->fp_offset = ap->fp_offset + 8;
  } else {
    addr = ap->overflow_arg_area;
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + 8;
  }
  return addr;
}

/* 32-bit cross targets (i386/arm32/riscv32): argument slots are 4 bytes (one
   machine word), not 8. A 64-bit variadic arg (double/long long) occupies two
   consecutive word slots, packed (no 8-byte alignment — pxx's own word-based
   call convention). reg_save_area holds the saved GP arg registers (a0..a7 =
   32 bytes on riscv32, r0..r3 = 16 on arm32, empty on i386-cdecl); the frontend
   passes the reg-area byte size in fp_offset. gp_offset walks the reg area, then
   overflow (caller stack). The frontend passes each arg's byte size so the walk
   steps by 4 or 8. */
void __pxx_va_start_impl32(struct __pxx_va_elem *ap, void *save,
                                  unsigned int gpbytes, void *overflow,
                                  unsigned int regsize) {
  ap->gp_offset = gpbytes;    /* reg-area bytes already consumed by named params */
  ap->fp_offset = regsize;    /* total reg-area byte size (0/16/32) */
  ap->reg_save_area = save;
  ap->overflow_arg_area = overflow;
}
void *__pxx_va_arg_cross32(struct __pxx_va_elem *ap, unsigned int size,
                           unsigned int align) {
  unsigned int step;
  void *addr;
  /* Round the byte size up to a whole 4-byte word slot. This used to read
     `(size <= 4) ? 4 : 8`, which is the same answer for every SCALAR (no C
     variadic scalar exceeds 8 bytes) and the wrong one for a STRUCT: an
     i386 cdecl aggregate occupies ceil(size/4) words of its own bytes, and
     the caller counts it that way. Identical bytes for 1..8; a
     generalisation, not a behaviour change, for anything the old form
     could not describe.
     bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer */
  step = (size + 3u) & ~3u;
  if (step < 4) step = 4;
  /* ALIGNMENT IS PER-TARGET AND THE FRONTEND ANSWERS IT, because the three
     targets sharing this walk genuinely disagree. AAPCS32 gives an 8-byte
     scalar 8-byte alignment, in registers and on the stack, for a variadic
     argument exactly as for a named one -- so `printf("%f", x)` on armel puts
     the double in r2:r3 and SKIPS r1. The RISC-V psABI explicitly does NOT
     require an aligned register pair, and i386 cdecl has no alignment at all;
     both pass align=4 and reach the packed walk this function has always done.
     Getting this wrong is silent: with the reg area walked 4 bytes early the
     double reads half padding and prints 0.00.
     bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area */
  if (align > 4) {
    ap->gp_offset = (ap->gp_offset + 7u) & ~7u;
    ap->overflow_arg_area =
        (void *)((((unsigned int)ap->overflow_arg_area) + 7u) & ~7u);
  }
  if (ap->gp_offset + step <= ap->fp_offset) {
    /* Fully inside the register-save area. */
    addr = (char *)ap->reg_save_area + ap->gp_offset;
    ap->gp_offset = ap->gp_offset + step;
  } else if (ap->gp_offset < ap->fp_offset) {
    /* STRADDLE: an 8-byte arg begins in the last reg-save word and continues in
       the caller's overflow (stack) area. pxx packs 64-bit variadic args as two
       words with NO 8-byte alignment, so one can span the reg/stack boundary
       (e.g. arm32: low word in r3, high word on the stack). The two halves are
       not contiguous in memory, so assemble them: the low half is already in the
       reg-save tail; copy the overflow half into the save-area slack immediately
       after it (the 176-byte __va_save uses only 16 bytes on arm32 / 32 on
       riscv32, so [fp_offset..] is free), then return the low-half address as one
       contiguous span. Advance overflow by ONLY the copied half — the next arg
       starts right after the high word, not a full step later (the old code
       skipped the reg word and read the whole 8 bytes from overflow, dropping the
       low half AND over-advancing, which shifted every following variadic arg). */
    unsigned int inReg = ap->fp_offset - ap->gp_offset;   /* bytes still in regs */
    unsigned int fromOvf = step - inReg;                  /* bytes taken from stack */
    char *lo = (char *)ap->reg_save_area + ap->gp_offset;
    char *hi = lo + inReg;
    unsigned int k;
    for (k = 0; k < fromOvf; k++) hi[k] = ((char *)ap->overflow_arg_area)[k];
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + fromOvf;
    ap->gp_offset = ap->fp_offset;
    addr = lo;
  } else {
    /* Fully past the reg area: the caller placed this arg on the stack. */
    addr = ap->overflow_arg_area;
    ap->overflow_arg_area = (char *)ap->overflow_arg_area + step;
  }
  return addr;
}

