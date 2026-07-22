/* &(T){expr} on a SCALAR compound literal — C99 6.5.2.5 gives it storage
   (bug-c-compound-literal-address-of). The value path yielded a converted
   VALUE, so & produced a bogus address and the read SIGSEGV'd. Also covers
   writing through the pointer and the float-bits reinterpret idiom. */
int main(void) {
    double s54 = *(double*)&(unsigned long long){0x4350000000000000ull};
    int *p = &(int){40};
    *p += 1;
    long ok_bits = (s54 == 18014398509481984.0);
    return *p + (int)ok_bits + (int)(*(&(long){0}));  /* 41 + 1 + 0 = 42 */
}
