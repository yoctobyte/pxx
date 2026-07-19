int printf(const char *fmt, ...);
typedef unsigned short uint16_t;
enum { KN = 0, KG = 1, KA = 2, KAG = 3 };
static const uint16_t map[] = {
    [KN] = 13,
    [KG] = 14,
    [KA] = 15,
    [KAG] = 16,
};
int main(void) {
    printf("%d %u %u %u %u\n", (int)(sizeof(map)/sizeof(map[0])), map[0], map[1], map[2], map[3]);
    if (sizeof(map)/sizeof(map[0]) == 4 && map[0] == 13 && map[3] == 16) return 42;
    return 1;
}
