/* Each target predefines ITS OWN arch macro and no other. `__x86_64__` used to
   be defined unconditionally on every target and no other arch macro ever was,
   so a cross-compile took every `#ifdef __x86_64__` branch — x86 inline asm
   offered to an ARM backend — and the portable `#else` a new target wants was
   unreachable. Nothing warned.

   Written as PREPROCESSOR assertions so it is meaningful when merely compiled
   for a cross target, not only when run. bug-cfront-arch-predefines-always-x86-64 */

#if defined(__riscv)
#  if __riscv_xlen != 32
#    error "riscv xlen"
#  endif
#  if defined(__x86_64__) || defined(__i386__) || defined(__aarch64__) || defined(__arm__)
#    error "riscv: another arch macro is also defined"
#  endif
#elif defined(__arm__)
#  if __ARM_ARCH != 7
#    error "arm arch"
#  endif
#  if defined(__x86_64__) || defined(__i386__) || defined(__aarch64__) || defined(__riscv)
#    error "arm: another arch macro is also defined"
#  endif
#elif defined(__aarch64__)
#  if defined(__x86_64__) || defined(__i386__) || defined(__arm__) || defined(__riscv)
#    error "aarch64: another arch macro is also defined"
#  endif
#elif defined(__i386__)
#  if defined(__x86_64__) || defined(__aarch64__) || defined(__arm__) || defined(__riscv)
#    error "i386: another arch macro is also defined"
#  endif
#elif defined(__x86_64__)
#  if defined(__i386__) || defined(__aarch64__) || defined(__arm__) || defined(__riscv)
#    error "x86-64: another arch macro is also defined"
#  endif
#else
#  error "no arch macro defined at all"
#endif

/* The data-model predefines must agree with the arch, not drift from it. */
#if defined(__x86_64__) || defined(__aarch64__)
#  if __SIZEOF_LONG__ != 8 || !defined(__LP64__)
#    error "64-bit target is not LP64"
#  endif
#else
#  if __SIZEOF_LONG__ != 4 || !defined(__ILP32__)
#    error "32-bit target is not ILP32"
#  endif
#endif

int main(void) { return 42; }
