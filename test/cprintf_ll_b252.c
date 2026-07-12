/* crtl printf: the `ll` length modifier must actually be honoured.

   printf counted the l's into `lng` but then only ever did va_arg(ap, long). On
   LP64 that works by accident (long == long long); on ILP32 a long is 32 bits, so
   %llx took only the LOW half of the argument AND left the HIGH half sitting in
   the varargs slot — which the NEXT conversion then consumed. One wrong value plus
   every later argument shifted (bug-crtl-printf-ll-ilp32).

   The give-away was `printf("%llx %d", v, 7)` printing the high half of v where the
   7 belonged.

   exit 42 = all pass. */

#include <stdio.h>
#include <string.h>

int main(void)
{
	char buf[64];
	unsigned long long v = 0xabcd00000000ULL;
	long long neg = -5000000000LL;   /* needs more than 32 bits */
	int tail = 7;

	snprintf(buf, sizeof buf, "%llx", v);
	if (strcmp(buf, "abcd00000000") != 0) return 1;

	/* the argument AFTER a %ll must not be eaten by the high half */
	snprintf(buf, sizeof buf, "%llx %d", v, tail);
	if (strcmp(buf, "abcd00000000 7") != 0) return 2;

	snprintf(buf, sizeof buf, "%llu", 12345678901ULL);
	if (strcmp(buf, "12345678901") != 0) return 3;

	snprintf(buf, sizeof buf, "%lld", neg);
	if (strcmp(buf, "-5000000000") != 0) return 4;

	/* a plain %d/%u after the widening must still read 32 bits */
	snprintf(buf, sizeof buf, "%d %u", -3, 4u);
	if (strcmp(buf, "-3 4") != 0) return 5;

	snprintf(buf, sizeof buf, "%llo", 8ULL);
	if (strcmp(buf, "10") != 0) return 6;

	return 42;
}
