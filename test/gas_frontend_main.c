/* Driver for test/gas_frontend.S (see there). */
#include <stdio.h>

long gas_sum(long a, long b);
long gas_count(long n);
long gas_rip(long v);
long gas_call_back(long v);
long gas_seven(void);
long gas_big(void);
long gas_pick(long i);
extern const char gas_strs[];
extern const int gas_span;

long c_helper(long v) { return v * 10; }

int main(void)
{
    printf("sum %ld count %ld rip %ld\n", gas_sum(4, 5), gas_count(9), gas_rip(23));
    printf("call %ld seven %ld big %ld\n", gas_call_back(6), gas_seven(), gas_big());
    printf("pick %d %d %d\n", gas_pick(0) == (long)gas_seven, gas_pick(1) == (long)gas_big,
           gas_pick(2) == (long)gas_sum);
    printf("strs %s %s %d %d %c span %d\n", gas_strs, gas_strs + 4, gas_strs[9], gas_strs[10],
           gas_strs[11], gas_span);
    return 0;
}
