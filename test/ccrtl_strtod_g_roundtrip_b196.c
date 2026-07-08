/* b196: crtl strtod + printf %g precision (bug-crtl-strtod-precision-cjson-floats).
   strtod accumulated the fraction via inexact 0.1 scaling (1-ulp drift:
   "0.0625" -> 0.062500000000000008) and %g normalised by repeated /10 (drift:
   100.125 printed as 100.12499999999999 at %1.15g). Both now go through exact
   integer-mantissa paths; exactly-representable values must round-trip
   bit-for-bit, cJSON style: parse -> %1.15g -> reparse -> compare. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *vals[] = {
    "-0.0625", "0.0625", "100.125", "0.001953125", "0.5", "0.25", "-2.75",
    "19.5", "1e22", "-1e-22", "123456789.5", "3.5e10", "0"
};

union bits { double d; unsigned long long u; };

int main(void) {
    char buf[64];
    int i;
    for (i = 0; i < (int)(sizeof(vals) / sizeof(vals[0])); i++) {
        union bits a, b;
        char *end;
        a.d = strtod(vals[i], &end);
        if (*end != 0) { printf("BAD end %s\n", vals[i]); return 1; }
        sprintf(buf, "%1.15g", a.d);
        b.d = strtod(buf, 0);
        if (a.u != b.u) {
            printf("ROUNDTRIP %s -> %s (bits %llx != %llx)\n",
                   vals[i], buf, a.u, b.u);
            return 2;
        }
    }
    /* the original red: -0.0625 must print shortest, no 17-digit tail */
    sprintf(buf, "%1.15g", strtod("-0.0625", 0));
    if (strcmp(buf, "-0.0625")) { printf("GOT %s\n", buf); return 3; }
    sprintf(buf, "%1.15g", strtod("100.125", 0));
    if (strcmp(buf, "100.125")) { printf("GOT %s\n", buf); return 4; }
    return 42;
}
