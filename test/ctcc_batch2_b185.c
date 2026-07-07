/* b185: tcc bring-up batch 2 —
   1. blue paint: a self-referential object macro must not re-expand on the
      rescan of an enclosing macro's output (tcc's `#define x s1->x` section
      shorthands gave `s1->s1->x`).
   2. labeled statement inside an unbraced if: label + statement are ONE
      statement (C 6.8.1); tcc's parse_define ran its ## error unconditionally.
   3. printf of a >1023-byte string: single fprintf/printf re-renders into a
      heap buffer instead of truncating. */
#include <stdio.h>
#include <string.h>

typedef struct { int eh_frame_section; int x; } St;
St g1; St *s1 = &g1;
#define eh_frame_section s1->eh_frame_section
#define dwarf_data4(s,e) ((s) = (e))

int hits = 0;
void boom(void) { hits++; }

int main(void)
{
    char big[2000];
    int n, once = 0, t0 = 5;

    dwarf_data4(eh_frame_section, 7);        /* paint: must hit g1's field */
    eh_frame_section += 1;
    if (*(int *)&g1 != 8) return 1;

    if (t0 == 7)
lab:
        boom();                              /* must NOT run (t0 == 5) */
    if (hits == 0 && !once) {
        once = 1;
        goto lab;                            /* second entry runs boom once */
    }
    if (hits != 1 || !once) return 3;

    memset(big, 'x', sizeof(big) - 2);
    big[sizeof(big) - 2] = '\n';
    big[sizeof(big) - 1] = 0;
    n = printf("%s", big);                   /* > 1023 bytes, one call */
    if (n != (int)sizeof(big) - 1) return 4;

    return 42;
}
