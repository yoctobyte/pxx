/* File-scope asm aliases, in the shapes of NetBSD sys/cdefs_elf.h:
   __strong_alias / __weak_alias on functions and data, __KERNEL_RCSID and
   __warn_references string sections (dropped). Linked under a gcc main
   (c_file_scope_asm_alias_main.c) that also overrides a weak alias.
   feature-c-file-scope-asm-symbol-aliases */
#define _C_LABEL_STRING(x) x
#define __strong_alias(alias,sym) \
    __asm(".global " _C_LABEL_STRING(#alias) "\n" \
          _C_LABEL_STRING(#alias) " = " _C_LABEL_STRING(#sym));
#define __weak_alias(alias,sym) \
    __asm(".weak " _C_LABEL_STRING(#alias) "\n" \
          _C_LABEL_STRING(#alias) " = " _C_LABEL_STRING(#sym));
#define __SECTIONSTRING(_sec, _str) \
    __asm(".pushsection " #_sec ",\"MS\",@progbits,1\n" \
          ".asciz \"" _str "\"\n" \
          ".popsection")
#define __KERNEL_RCSID(_n, _s) __SECTIONSTRING(.ident, _s)
#define __warn_references(sym,msg) \
    __asm(".pushsection .gnu.warning." #sym "\n" \
          ".ascii \"" msg "\"\n" \
          ".popsection");

__KERNEL_RCSID(0, "$NetBSD: al.c,v 1.1 2026/11/18 test $");

long ufetch_64(const long *p) { return *p + 1; }
__strong_alias(ufetch_long, ufetch_64)
__strong_alias(ufetch_ptr, ufetch_64)

static int counter_impl = 40;
int counter_base = 2;
__strong_alias(counter_alias, counter_base)

int mutex_exit_impl(int x) { return x * 3 + counter_impl; }
__weak_alias(mutex_spin_exit, mutex_exit_impl)
__weak_alias(overridden, mutex_exit_impl)

int old_api(void) { return 5; }
__warn_references(old_api, "old_api is obsolete; use new_api # really")
