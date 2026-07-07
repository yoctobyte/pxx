/* b190 (feature-c-corpus-tcc): &floatObject passed as a void-pointer/integer-typed
   argument. The address value kept the POINTEE's float type tag, so the C
   float->int-parameter truncation cvttsd2si'd the ADDRESS BITS — tcc's
   write_ldouble(ptr, &vtop->c.ld) received s=0 and crashed. Exit 42 = pass. */
struct U { long long a; double d; };
static long long readq(void *s) { return *(long long *)s; }
static double g;
int main(void) {
    struct U u;
    u.d = 3.5;
    g = 2.5;
    if (readq(&u.d) != 0x400C000000000000LL) return 1;
    if (readq(&g) != 0x4004000000000000LL) return 2;
    return 42;
}
