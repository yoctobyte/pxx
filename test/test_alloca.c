#include <stdio.h>
#include <string.h>

int depth_sum(int n) {
    /* variable-size alloca; called in a loop — frame must not leak */
    char *buf = alloca(n + 1);
    int i, s = 0;
    for (i = 0; i < n; i++) buf[i] = (char)('a' + (i % 26));
    buf[n] = 0;
    for (i = 0; i < n; i++) s += buf[i];
    /* second alloca in the same frame */
    int *nums = __builtin_alloca(4 * sizeof(int));
    for (i = 0; i < 4; i++) nums[i] = i * 10;
    return s + nums[3] + (int)strlen(buf);
}

int main(void) {
    int i, total = 0;
    for (i = 1; i <= 2000; i++) total += depth_sum(i % 64 + 1);
    printf("%d\n", total);
    return 0;
}
