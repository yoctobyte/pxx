/* Gibux item 6: an object that only DECLARES a big array (`extern struct proc
   procs[128];` from a header) used to reserve a private, never-addressed .bss
   slot of the array's full size -- ten Gibux objects carried 5.5 MB that way.
   This object declares two big imports between real .bss variables of its own,
   so dropping the slots moves every variable above them: their addresses,
   and the relocations that reach them, must still be right.
   Linked with c_extern_array_reserves_no_bss_def.c; see
   tools/check_extern_bss.sh. */
#include <stdio.h>

struct rec { long a, b; char tag[48]; };

static int before[3];                   /* below the holes */
extern int big[65536];                  /* 256 KB, defined in the other object */
static long between[5];
extern struct rec recs[1000];           /* 64 KB */
static char after[40];                  /* above both holes */
static int *const pbig = &big[7];       /* .data pointing into an import */
static long *pbetween = &between[2];    /* .data pointing into a moved slot */
int seen_from_def;                      /* global .bss, read by the other object */

void fill_def(void);
int check_def(void);

int main(void)
{
    fill_def();
    before[2] = 11;
    between[4] = 22;
    after[39] = 33;
    *pbetween = 44;
    seen_from_def = 55;
    big[65535] = big[7] + 1;
    recs[999].b = recs[0].a + 1;
    printf("before %d between %ld %ld after %d\n", before[2], between[4], between[2], after[39]);
    printf("big %d %d %d via %d\n", big[0], big[7], big[65535], *pbig);
    printf("recs %ld %ld %s\n", recs[0].a, recs[999].b, recs[500].tag);
    printf("def sees %d\n", check_def());
    return 0;
}
