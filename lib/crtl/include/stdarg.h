#ifndef PXX_CRTL_STDARG_H
#define PXX_CRTL_STDARG_H 1

/* System V AMD64 va_list: a 24-byte control block. A plain struct (passed by
   value between functions); the reg_save_area pointer it carries refers to the
   originating frame, which stays live for the call, so a callee can va_arg on
   its copy (lua's luaL_error -> lua_pushvfstring pattern). */
typedef struct __pxx_va_elem {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
} __pxx_va_elem;

typedef struct __pxx_va_elem va_list;

/* 176-byte register-save area: 6 GP slots (48) + 8 XMM slots (16 each). The
   variadic prologue stores the incoming arg registers here; one of these is
   declared as a hidden local in every variadic function. */
typedef struct __pxx_va_save { char bytes[176]; } __pxx_va_save;

/* va_start, in plain C: seed the control block. ngp/nfp = number of named GP /
   FP(XMM) params already consumed (so the first variadic arg of each class is
   read next). The GP save region starts at offset 0, the XMM region at 48, so
   gp_offset skips ngp 8-byte slots and fp_offset skips nfp 16-byte XMM slots
   past the region base. overflow points at the first caller stack slot past the
   six GP registers. */
static void __pxx_va_start_impl(struct __pxx_va_elem *ap, void *save,
                                unsigned int ngp, void *overflow,
                                unsigned int nfp) {
  ap->gp_offset = ngp * 8;
  ap->fp_offset = 48 + nfp * 16;
  ap->reg_save_area = save;
  ap->overflow_arg_area = overflow;
}

/* va_arg gp/fp/overflow walk, in plain C. Returns the address of the next
   integer/pointer (gp) or floating (fp) variadic argument and advances. */
static void *__pxx_va_arg_gp(struct __pxx_va_elem *ap) {
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
static void *__pxx_va_arg_fp(struct __pxx_va_elem *ap) {
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

/* va_start/va_arg/va_end are handled by the frontend (it knows the save-area
   local and the named-GP count); these macros stay for source compatibility. */
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_end(ap)         __builtin_va_end(ap)
#define va_copy(d, s)      __builtin_va_copy(d, s)

#endif
