int printf(const char *fmt, ...);
typedef unsigned int uint32_t;
typedef unsigned char uint8_t;
typedef struct H { int rc; } H;
struct S {
    H header;
    uint32_t len : 31;
    uint8_t wide : 1;
    uint32_t hash : 30;
    uint8_t atype : 2;
    uint32_t hash_next;
    void *weak;
};
int main(void) {
    struct S s;
    unsigned long sz = sizeof(struct S);
    s.len = 123456; s.wide = 1; s.hash = 777; s.atype = 2; s.hash_next = 9;
    printf("sizeof=%lu len=%u wide=%u hash=%u atype=%u next=%u\n",
        sz, (unsigned)s.len, (unsigned)s.wide, (unsigned)s.hash, (unsigned)s.atype, s.hash_next);
    if (sz == 24 && s.len == 123456 && s.wide == 1 && s.hash == 777 && s.atype == 2) return 42;
    return 1;
}
