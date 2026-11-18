/* gcc's builtins with NO header in scope, as NetBSD rump code uses them
   (sys/endian.h's be16enc calls __builtin_memcpy; bitops call __builtin_ffs).
   pxx renamed them to functions declared only in crtl headers, so a unit
   with no #include failed with "call to undeclared function".
   bug-c-builtin-needs-a-header-in-a-hosted-unit */
int printf(const char *, ...);

static void be32enc(void *buf, unsigned int v)
{
    unsigned int be = __builtin_bswap32(v);
    __builtin_memcpy(buf, &be, sizeof(be));
}

int main(void)
{
    unsigned char b[8];
    __builtin_memset(b, 0xee, sizeof(b));
    be32enc(b, 0x11223344u);
    char s[16];
    __builtin_strcpy(s, "rump");
    printf("%02x%02x%02x%02x %02x %lu %d\n", b[0], b[1], b[2], b[3], b[4],
           (unsigned long)__builtin_strlen(s), __builtin_memcmp(b, "\x11\x22", 2));
    printf("%d %d %d %d\n", __builtin_ffs(0), __builtin_ffs(8), __builtin_ffsll(1ULL << 40),
           __builtin_strcmp(s, "rump"));
    char *p = __builtin_malloc(4);
    __builtin_memcpy(p, "ok", 3);
    printf("%s\n", p);
    __builtin_free(p);
    return 0;
}
