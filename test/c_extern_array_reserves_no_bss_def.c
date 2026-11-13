/* The defining half of c_extern_array_reserves_no_bss_use.c. */
struct rec { long a, b; char tag[48]; };

int big[65536];
struct rec recs[1000];
extern int seen_from_def;

void fill_def(void)
{
    big[0] = 1;
    big[7] = 70;
    recs[0].a = 100;
    recs[500].tag[0] = 'o';
    recs[500].tag[1] = 'k';
}

int check_def(void)
{
    return seen_from_def + big[65535] + (int)recs[999].b;
}
