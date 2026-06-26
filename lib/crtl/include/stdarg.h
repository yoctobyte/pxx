#ifndef PXX_CRTL_STDARG_H
#define PXX_CRTL_STDARG_H 1

/* System V AMD64 va_list: a 24-byte control block. Declared as an array[1] so a
   `va_list` lvalue decays to a pointer when passed to another function (matching
   the platform ABI and lua's luaL_error -> lua_pushvfstring pattern). */
typedef struct __pxx_va_elem {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
} __builtin_va_list[1];

typedef __builtin_va_list va_list;

/* The gp/fp-offset + overflow walk, in plain C (no special codegen). Returns the
   address of the next integer/pointer (gp) or floating (fp) variadic argument and
   advances the control block. The register-save area holds 6 GP slots (48 bytes)
   then 8 XMM slots (16 bytes each, to 176). */
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

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_end(ap)         __builtin_va_end(ap)
#define va_copy(d, s)      __builtin_va_copy(d, s)

#endif
