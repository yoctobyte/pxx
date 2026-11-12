/* Driver for c_freestanding_object_has_no_runtime_hooks.c: gcc links the pxx
   freestanding object and calls its variadic fs_vsum, so va_arg is run, not
   only present. With 8 arguments the last ones arrive on the stack. */
#include <stdio.h>
long fs_vsum(int n, ...);
int main(void)
{
    printf("%ld %ld\n", fs_vsum(3, 1L, 20L, 300L), fs_vsum(8, 1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L));
    return 0;
}
