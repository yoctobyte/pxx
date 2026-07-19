int printf(const char *fmt, ...);
typedef unsigned int uint32_t;
typedef long long int64_t;
enum { TOBJ = -1, TSTR = -7 };
static int classify(int64_t t64) {
    uint32_t tag = t64;
    switch (tag) {
    case TOBJ: return 10;
    case TSTR: return 20;
    case 3: return 30;
    default: return -1;
    }
}
int main(void) {
    if (classify(-1) != 10) { printf("bad %d\n", classify(-1)); return 1; }
    if (classify(-7) != 20) return 2;
    if (classify(3) != 30) return 3;
    printf("ok\n");
    return 42;
}
