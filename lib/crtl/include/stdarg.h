/* SPDX-License-Identifier: Zlib */
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

typedef struct __pxx_va_elem va_list[1];

/* 176-byte register-save area: 6 GP slots (48) + 8 XMM slots (16 each). The
   variadic prologue stores the incoming arg registers here; one of these is
   declared as a hidden local in every variadic function. */
typedef struct __pxx_va_save { char bytes[176]; } __pxx_va_save;

/* The implementations live in lib/crtl/src/stdarg.c, auto-pulled as this
   header's sibling. They were `static` DEFINITIONS here until 2026-08-19, which
   meant every translation unit that saw this header emitted its own copy — and
   the crtl auto-pull for a hand-declared prototype must include stdarg.h, so a
   single C program emitted them TWICE (+2204 bytes). A header carrying bodies
   cannot be included twice for free, which is the one thing a header is for.
   See bug-c-header-with-a-body-compiles-twice-across-the-macro-reset.

   The frontend resolves these by NAME (`FindProc('__pxx_va_arg_gp')` and
   friends in cparser.inc), so they must keep external linkage — declaring them
   `static` here again would break `va_arg` lowering, not merely re-bloat it. */
void __pxx_va_start_impl(struct __pxx_va_elem *ap, void *save,
                         unsigned int ngp, void *overflow, unsigned int nfp);
void *__pxx_va_arg_gp(struct __pxx_va_elem *ap);
void *__pxx_va_arg_fp(struct __pxx_va_elem *ap);
void *__pxx_va_arg_cross(struct __pxx_va_elem *ap);
void __pxx_va_start_impl32(struct __pxx_va_elem *ap, void *save,
                           unsigned int gpbytes, void *overflow,
                           unsigned int regsize);
void *__pxx_va_arg_cross32(struct __pxx_va_elem *ap, unsigned int size);

/* va_start/va_arg/va_end are handled by the frontend (it knows the save-area
   local and the named-GP count); these macros stay for source compatibility. */
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type)   __builtin_va_arg(ap, type)
#define va_end(ap)         __builtin_va_end(ap)
#define va_copy(d, s)      __builtin_va_copy(d, s)

#endif
