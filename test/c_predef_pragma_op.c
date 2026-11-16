/* gcc's predefined type macros (__SIZE_TYPE__ & co, __ELF__) and the C99
   _Pragma operator, as NetBSD's sys/common_ansi.h and sys/cdefs.h use them.
   bug-c-gcc-predefined-type-macros-and-pragma-operator-missing */
#include <stdio.h>
#ifndef __ELF__
#error no __ELF__
#endif
typedef __SIZE_TYPE__ my_size_t;
typedef __PTRDIFF_TYPE__ my_ptrdiff_t;
typedef __INT64_TYPE__ my_i64;
typedef __UINT32_TYPE__ my_u32;
typedef __INTPTR_TYPE__ my_intptr;
typedef __WCHAR_TYPE__ my_wchar;
#define BEGIN_PUBLIC _Pragma("GCC visibility push(default)")
#define END_PUBLIC _Pragma("GCC visibility pop")
#define PACKED_BEGIN _Pragma("pack(push, 1)")
#define PACKED_END _Pragma("pack(pop)")
BEGIN_PUBLIC
int pub = 7;
END_PUBLIC
PACKED_BEGIN
struct pk { char c; int i; };
PACKED_END
struct np { char c; int i; };
#define X 1
_Pragma("push_macro(\"X\")")
#undef X
#define X 2
int inner = X;
_Pragma("pop_macro(\"X\")")
int outer = X;
int main(void) {
    const char *s = "_Pragma(\"pack(1)\") stays text";
    printf("sizes %d %d %d %d %d %d\n", (int)sizeof(my_size_t), (int)sizeof(my_ptrdiff_t),
           (int)sizeof(my_i64), (int)sizeof(my_u32), (int)sizeof(my_intptr), (int)sizeof(my_wchar));
    printf("max %d %d\n", __INT32_MAX__ == 2147483647, __SIZE_MAX__ == (my_size_t)-1);
    printf("c %d\n", (int)(__INT64_C(1) << 40 > 0));
    printf("pub %d pk %d np %d\n", pub, (int)sizeof(struct pk), (int)sizeof(struct np));
    printf("macro %d %d\n", inner, outer);
    printf("%s\n", s);
    return 0;
}
