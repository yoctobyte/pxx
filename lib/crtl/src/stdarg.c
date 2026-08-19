/* SPDX-License-Identifier: Zlib */
/* va_list helpers — the bodies that used to sit in <stdarg.h>.

   Moved here 2026-08-19 (bug-c-header-with-a-body-compiles-twice-across-the-
   macro-reset). They are auto-pulled as this header's sibling, once per compile
   (CrtlSrcPulled in defs.inc), so including stdarg.h twice is now free.

   External linkage is required, not stylistic: cparser.inc resolves each of
   these by name via FindProc when lowering __builtin_va_start / __builtin_va_arg. */
#include <stdarg.h>

/* va_start, in plain C: seed the control block. ngp/nfp = number of named GP /
   FP(XMM) params already consumed (so the first variadic arg of each class is
   read next). The GP save region starts at offset 0, the XMM region at 48, so
   gp_offset skips ngp 8-byte slots and fp_offset skips nfp 16-byte XMM slots
   past the region base. overflow points at the first caller stack slot past the
   six GP registers. */
void __pxx_va_start_impl(struct __pxx_va_elem *ap, void *save,
                                unsigned int ngp, void *overflow,
                                unsigned int nfp) {
  ap->gp_offset = ngp * 8;
  ap->fp_offset = 48 + nfp * 16;
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

/* Cross-target (aarch64) variadic model: the pxx value model passes every scalar
   — floats included — as bits in a general argument register, so there is ONE
   register save area of 8 eight-byte slots (x0..x7 = 64 bytes) and no separate
   FP region. va_arg reads that area for every type, then spills to overflow.
   Seeded via __pxx_va_start_impl (gp_offset = nnamed*8, reg_save_area, overflow;
   fp_offset unused). x86-64 keeps its two-class SysV helpers above. */
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
void *__pxx_va_arg_cross32(struct __pxx_va_elem *ap, unsigned int size) {
  unsigned int step;
  void *addr;
  step = (size <= 4) ? 4 : 8;
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

