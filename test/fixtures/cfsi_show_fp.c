/* The float half of test/c_file_scope_initialisers_are_data.c's second line,
   built by gcc: the --freestanding object may not touch SSE, so it hands
   its baked float/double over by address and this prints them. */
#include <stdio.h>
void cfsi_show_fp(const double *r, const float *h, const double *f)
{
    printf("%.2f %.2f %.1f\n", *r, (double)*h, *f);
}
