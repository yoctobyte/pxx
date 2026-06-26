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

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_end(ap)         __builtin_va_end(ap)
#define va_copy(d, s)      __builtin_va_copy(d, s)

#endif
